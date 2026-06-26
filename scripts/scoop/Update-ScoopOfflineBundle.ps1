# 修正版：所有可能为单对象的流水线结果均显式包装为数组，兼容 Set-StrictMode。
[CmdletBinding()]
param(
    # 同步到内网后的离线 Bundle 目录。
    [string]$BundleRoot = 'D:\ScoopOfflineBundle',

    # 已部署的内网 Scoop 根目录。
    [string]$ScoopRoot = 'D:\scoop',

    # 留空时优先采用用户环境变量 SCOOP_CACHE，否则使用 D:\scoop\cache。
    [string]$CacheRoot = '',

    # 只更新 Scoop 核心、main/extras bucket 与 cache，不更新已安装应用。
    [switch]$SkipAppUpdate,

    # 若 Code / clangd / clang / cmake / ninja 正在运行，显式指定后会强制结束它们。
    [switch]$StopRunningProcesses,

    # 成功后保留最近多少份 core/bucket 备份。0 表示不保留。
    [ValidateRange(0, 20)]
    [int]$KeepBackupCount = 2
)

Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Resolve-FullPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if ($fullPath.Length -gt 3) {
        $fullPath = $fullPath.TrimEnd('\')
    }

    return $fullPath
}

function Get-OSArchitecture {
    $rawArchitecture = if ($env:PROCESSOR_ARCHITEW6432) {
        $env:PROCESSOR_ARCHITEW6432
    }
    else {
        $env:PROCESSOR_ARCHITECTURE
    }

    switch ($rawArchitecture.ToUpperInvariant()) {
        'AMD64' { return '64bit' }
        'ARM64' { return 'arm64' }
        default { return '32bit' }
    }
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExpectedHash
    )

    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash

    if ($actualHash -ine $ExpectedHash) {
        throw "SHA-256 校验失败：$Path"
    }
}

function Add-HardLinkOrCopy {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    $parent = Split-Path -Path $Destination -Parent
    New-Item -ItemType Directory -Path $parent -Force | Out-Null

    $sourceDrive = [System.IO.Path]::GetPathRoot($Source)
    $destinationDrive = [System.IO.Path]::GetPathRoot($Destination)

    if ($sourceDrive -ieq $destinationDrive) {
        try {
            New-Item `
                -ItemType HardLink `
                -Path $Destination `
                -Target $Source `
                -ErrorAction Stop | Out-Null

            return
        }
        catch {
            Write-Warning "无法创建 cache 硬链接，改为复制：$(Split-Path $Source -Leaf)"
        }
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Ensure-CacheFile {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [Int64]$ExpectedLength,

        [Parameter(Mandatory)]
        [string]$ExpectedHash
    )

    if (Test-Path -LiteralPath $Destination) {
        $existing = Get-Item -LiteralPath $Destination -Force
        $isValid = $existing.Length -eq $ExpectedLength

        if ($isValid) {
            $existingHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
            $isValid = $existingHash -ieq $ExpectedHash
        }

        if ($isValid) {
            return
        }

        Write-Warning "发现同名但不匹配的旧 cache，正在替换：$(Split-Path $Destination -Leaf)"
        Remove-Item -LiteralPath $Destination -Force
    }

    Add-HardLinkOrCopy -Source $Source -Destination $Destination
}

function Add-UserPathEntry {
    param(
        [Parameter(Mandatory)]
        [string]$PathEntry
    )

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')

    $entries = @(
        $userPath -split ';' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $exists = @(
        $entries |
            Where-Object {
                $_.TrimEnd('\') -ieq $PathEntry.TrimEnd('\')
            }
    )

    if ($exists.Count -eq 0) {
        $newPath = ((@($PathEntry) + $entries) -join ';')

        [Environment]::SetEnvironmentVariable(
            'Path',
            $newPath,
            'User'
        )
    }

    $processEntries = @(
        $env:Path -split ';' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $processHasEntry = @(
        $processEntries |
            Where-Object {
                $_.TrimEnd('\') -ieq $PathEntry.TrimEnd('\')
            }
    )

    if ($processHasEntry.Count -eq 0) {
        $env:Path = "$PathEntry;$env:Path"
    }
}

function New-ScoopCommandShim {
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $shimDirectory = Join-Path $Root 'shims'
    New-Item -ItemType Directory -Path $shimDirectory -Force | Out-Null

    # 使用相对路径，因此 Scoop 根目录不依赖外网机的盘符。
    $cmdShim = @'
@echo off
setlocal
set "SCOOP_PS=%~dp0..\apps\scoop\current\bin\scoop.ps1"

where pwsh.exe >nul 2>&1
if not errorlevel 1 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%SCOOP_PS%" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCOOP_PS%" %*
)

exit /b %ERRORLEVEL%
'@

    Set-Content `
        -LiteralPath (Join-Path $shimDirectory 'scoop.cmd') `
        -Value $cmdShim `
        -Encoding ASCII
}

function Get-PackageNameFromSpec {
    param(
        [Parameter(Mandatory)]
        [string]$Spec
    )

    return (($Spec.Trim().Replace('\', '/') -split '/')[-1])
}

function Invoke-ScoopChildProcess {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    Write-Host ">> scoop $($Arguments -join ' ')" -ForegroundColor Cyan

    & $script:PowerShellExe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $script:ScoopPs1 `
        @Arguments

    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "Scoop 命令失败，退出码：$exitCode"
    }
}

function Move-DirectoryIfExists {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (Test-Path -LiteralPath $Source) {
        New-Item -ItemType Directory -Path (Split-Path -Path $Destination -Parent) -Force |
            Out-Null

        Move-Item -LiteralPath $Source -Destination $Destination
        return $true
    }

    return $false
}

$BundleRoot = Resolve-FullPath $BundleRoot
$ScoopRoot = Resolve-FullPath $ScoopRoot

$metadataPath = Join-Path $BundleRoot 'bundle.json'
$coreZip = Join-Path $BundleRoot 'scoop-core.zip'
$bucketsZip = Join-Path $BundleRoot 'buckets.zip'
$bundleCache = Join-Path $BundleRoot 'cache'

foreach ($path in @($metadataPath, $coreZip, $bucketsZip, $bundleCache)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "离线 Bundle 不完整，缺少：$path"
    }
}

$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json

if ([int]$metadata.FormatVersion -notin @(1, 2)) {
    throw "不支持的 Bundle 格式版本：$($metadata.FormatVersion)"
}

$localArchitecture = Get-OSArchitecture

if ([string]$metadata.Architecture -ne $localArchitecture) {
    throw @"
离线 Bundle 与当前机器架构不一致。

Bundle：$($metadata.Architecture)
当前：$localArchitecture
"@
}

Assert-Sha256 -Path $coreZip -ExpectedHash ([string]$metadata.ScoopCoreSha256)
Assert-Sha256 -Path $bucketsZip -ExpectedHash ([string]$metadata.BucketsSha256)

$scoopCurrent = Join-Path $ScoopRoot 'apps\scoop\current'
$oldScoopPs1 = Join-Path $scoopCurrent 'bin\scoop.ps1'

if (-not (Test-Path -LiteralPath $oldScoopPs1)) {
    throw @"
未找到已部署的 Scoop 核心：$oldScoopPs1

这是后续更新脚本；首次部署请使用 Install-ScoopOfflineBundle.ps1。
"@
}

if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    # Scoop 的优先级是环境变量 SCOOP_CACHE，再到 config.json 的 cache_path。
    $CacheRoot = [Environment]::GetEnvironmentVariable('SCOOP_CACHE', 'User')

    if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
        $CacheRoot = $env:SCOOP_CACHE
    }

    if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
        $configPath = Join-Path $HOME '.config\scoop\config.json'

        if (Test-Path -LiteralPath $configPath) {
            try {
                $scoopConfig = Get-Content -LiteralPath $configPath -Raw |
                    ConvertFrom-Json

                $cachePathProperty = $scoopConfig.PSObject.Properties['cache_path']

                if ($cachePathProperty -and -not [string]::IsNullOrWhiteSpace([string]$cachePathProperty.Value)) {
                    $CacheRoot = [string]$cachePathProperty.Value
                }
            }
            catch {
                Write-Warning "无法读取 Scoop 配置文件，将回退默认 cache：$configPath"
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
        $CacheRoot = Join-Path $ScoopRoot 'cache'
    }
}

$CacheRoot = Resolve-FullPath ([Environment]::ExpandEnvironmentVariables($CacheRoot))
New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null

# 先验证 Bundle 中每一个 cache 文件。验证完成后才会改动已部署的 Scoop。
$cacheInfos = @($metadata.CacheFiles)

if ($cacheInfos.Count -eq 0) {
    throw 'Bundle 元数据没有 cache 文件记录。'
}

foreach ($cacheInfo in $cacheInfos) {
    $source = Join-Path $bundleCache ([string]$cacheInfo.Name)

    if (-not (Test-Path -LiteralPath $source)) {
        throw "Bundle cache 缺少文件：$($cacheInfo.Name)"
    }

    $sourceInfo = Get-Item -LiteralPath $source -Force

    if ($sourceInfo.Length -ne [Int64]$cacheInfo.Length) {
        throw "Bundle cache 文件大小不匹配：$($cacheInfo.Name)"
    }

    Assert-Sha256 -Path $source -ExpectedHash ([string]$cacheInfo.Sha256)
}

# 准备 staging。必须和 ScoopRoot 在同一卷，后面的目录切换才能使用快速 Move-Item。
$updateId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$workRoot = Join-Path $ScoopRoot ".offline-update\$updateId"
$coreStageRoot = Join-Path $workRoot 'core'
$bucketStageRoot = Join-Path $workRoot 'buckets'
$failedRoot = Join-Path $workRoot 'failed'
$backupRoot = Join-Path $ScoopRoot "offline-backups\$updateId"

New-Item -ItemType Directory -Path @($coreStageRoot, $bucketStageRoot, $failedRoot) -Force |
    Out-Null

try {
    Expand-Archive -LiteralPath $coreZip -DestinationPath $coreStageRoot -Force
    Expand-Archive -LiteralPath $bucketsZip -DestinationPath $bucketStageRoot -Force
}
catch {
    throw "解压 Bundle 失败：$($_.Exception.Message)"
}

$stagedScoopCurrent = Join-Path $coreStageRoot 'apps\scoop\current'

if (-not (Test-Path -LiteralPath (Join-Path $stagedScoopCurrent 'bin\scoop.ps1'))) {
    throw "Bundle 解压内容不符合预期，缺少 Scoop 主脚本：$stagedScoopCurrent\bin\scoop.ps1"
}

# Build 脚本会根据实际软件自动打包 main、extras、versions 等 bucket。
# 因此更新脚本不能再把 bucket 固定为 main / extras。
$bundleBuckets = @(
    Get-ChildItem -LiteralPath $bucketStageRoot -Directory -Force |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName 'bucket')
        } |
        Select-Object -ExpandProperty Name |
        Sort-Object -Unique
)

if ($bundleBuckets.Count -eq 0) {
    throw "Bundle 解压后没有找到有效 bucket：$bucketStageRoot"
}

$bundledBucketsProperty = $metadata.PSObject.Properties['BundledBuckets']

if ($null -ne $bundledBucketsProperty) {
    $declaredBuckets = @(
        @($bundledBucketsProperty.Value) |
            ForEach-Object { [string]$_ } |
            Sort-Object -Unique
    )

    $missingBuckets = @(
        $declaredBuckets |
            Where-Object { $_ -notin $bundleBuckets }
    )

    if ($missingBuckets.Count -gt 0) {
        throw "Bundle 元数据声明但压缩包中缺少 bucket：$($missingBuckets -join ', ')"
    }
}

# Scoop 更新会跳过正在运行的程序。这里先明确处理，避免脚本显示成功但 VS Code 实际未更新。
$processNames = @('Code', 'clangd', 'clang', 'clang++', 'cmake', 'ninja', 'WindowsTerminal', 'WindowsTerminalPreview')
$foundProcesses = foreach ($name in $processNames) {
    Get-Process -Name $name -ErrorAction SilentlyContinue
}

# Sort-Object 仅返回一个项目时会把它展开为标量；外层 @() 保证后续始终是数组。
$runningProcesses = @(
    @($foundProcesses) |
        Sort-Object Id -Unique
)

if ($runningProcesses.Count -gt 0) {
    $processSummary = $runningProcesses |
        ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" } |
        Sort-Object -Unique

    if (-not $StopRunningProcesses) {
        throw @"
以下进程正在运行：
$($processSummary -join "`r`n")

请先关闭它们后重试；或确认可强制终止后加 -StopRunningProcesses。
"@
    }

    Write-Warning "正在强制结束：$($processSummary -join ', ')"
    $runningProcesses | Stop-Process -Force
    Start-Sleep -Seconds 1
}

# 先补齐 / 校验本地 cache。旧 cache 不删除，只新增 Bundle 中的新版本。
foreach ($cacheInfo in $cacheInfos) {
    $source = Join-Path $bundleCache ([string]$cacheInfo.Name)
    $destination = Join-Path $CacheRoot ([string]$cacheInfo.Name)

    Ensure-CacheFile `
        -Source $source `
        -Destination $destination `
        -ExpectedLength ([Int64]$cacheInfo.Length) `
        -ExpectedHash ([string]$cacheInfo.Sha256)
}

# 将 Scoop 核心以及 main / extras bucket 逐目录替换。
# persist、apps 下已安装软件、shims（除 scoop.cmd）和其他 bucket 都不会删除。
$bucketRoot = Join-Path $ScoopRoot 'buckets'
$scoopAppRoot = Join-Path $ScoopRoot 'apps\scoop'

New-Item -ItemType Directory -Path @($bucketRoot, $scoopAppRoot, $backupRoot) -Force |
    Out-Null

$swapState = @{
    CoreOldMoved = $false
    CoreNewMoved = $false
    BucketOldMoved = @{}
    BucketNewMoved = @{}
}

try {
    $oldCoreBackup = Join-Path $backupRoot 'scoop-current'
    $swapState.CoreOldMoved = Move-DirectoryIfExists `
        -Source $scoopCurrent `
        -Destination $oldCoreBackup

    Move-Item -LiteralPath $stagedScoopCurrent -Destination $scoopCurrent
    $swapState.CoreNewMoved = $true

    foreach ($bucket in $bundleBuckets) {
        $target = Join-Path $bucketRoot $bucket
        $stage = Join-Path $bucketStageRoot $bucket
        $backup = Join-Path $backupRoot "buckets\$bucket"

        $swapState.BucketOldMoved[$bucket] = Move-DirectoryIfExists `
            -Source $target `
            -Destination $backup

        Move-Item -LiteralPath $stage -Destination $target
        $swapState.BucketNewMoved[$bucket] = $true
    }
}
catch {
    $originalError = $_
    Write-Warning '替换 Scoop 核心或 Bucket 失败，正在回滚。'

    foreach ($bucket in @($bundleBuckets | Sort-Object -Descending)) {
        $target = Join-Path $bucketRoot $bucket
        $backup = Join-Path $backupRoot "buckets\$bucket"
        $failed = Join-Path $failedRoot "buckets\$bucket"

        try {
            if ($swapState.BucketNewMoved[$bucket] -and (Test-Path -LiteralPath $target)) {
                Move-DirectoryIfExists -Source $target -Destination $failed | Out-Null
            }

            if ($swapState.BucketOldMoved[$bucket] -and (Test-Path -LiteralPath $backup)) {
                Move-DirectoryIfExists -Source $backup -Destination $target | Out-Null
            }
        }
        catch {
            Write-Warning "Bucket 回滚失败：$bucket。请检查 $backup 与 $failed。"
        }
    }

    $failedCore = Join-Path $failedRoot 'scoop-current'
    $oldCoreBackup = Join-Path $backupRoot 'scoop-current'

    try {
        if ($swapState.CoreNewMoved -and (Test-Path -LiteralPath $scoopCurrent)) {
            Move-DirectoryIfExists -Source $scoopCurrent -Destination $failedCore | Out-Null
        }

        if ($swapState.CoreOldMoved -and (Test-Path -LiteralPath $oldCoreBackup)) {
            Move-DirectoryIfExists -Source $oldCoreBackup -Destination $scoopCurrent | Out-Null
        }
    }
    catch {
        Write-Warning "Scoop 核心回滚失败。请检查 $oldCoreBackup 与 $failedCore。"
    }

    throw $originalError
}

# 使用新的 Scoop 核心，并写入最新同步时间。
# 这样随后执行 `scoop update <app>` 时不会因“超过 3 小时未更新”而尝试 Git 同步。
$script:ScoopPs1 = Join-Path $scoopCurrent 'bin\scoop.ps1'

if (-not (Test-Path -LiteralPath $script:ScoopPs1)) {
    throw "替换后找不到 Scoop 主脚本：$script:ScoopPs1"
}

$script:PowerShellExe = (Get-Process -Id $PID).Path

if (-not $script:PowerShellExe -or -not (Test-Path -LiteralPath $script:PowerShellExe)) {
    $script:PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
}

$env:SCOOP = $ScoopRoot
$env:SCOOP_CACHE = $CacheRoot

[Environment]::SetEnvironmentVariable('SCOOP', $ScoopRoot, 'User')
[Environment]::SetEnvironmentVariable('SCOOP_CACHE', $CacheRoot, 'User')

New-ScoopCommandShim -Root $ScoopRoot
Add-UserPathEntry -PathEntry (Join-Path $ScoopRoot 'shims')

Invoke-ScoopChildProcess -Arguments @(
    'config',
    'LAST_UPDATE',
    (Get-Date).ToString('o')
)

if (-not $SkipAppUpdate) {
    $packageEntries = @($metadata.DownloadedPackages)

    if ($packageEntries.Count -eq 0) {
        throw 'Bundle 元数据没有 DownloadedPackages，无法确定要更新的应用。'
    }

    # 先收集，再排序；不能把 foreach 语句的闭合大括号直接接到管道符。
    $appsToUpdate = @(
        foreach ($entry in $packageEntries) {
            $spec = [string]$entry.Spec

            if ([string]::IsNullOrWhiteSpace($spec)) {
                continue
            }

            $nameProperty = $entry.PSObject.Properties['Name']
            $name = if ($null -ne $nameProperty -and -not [string]::IsNullOrWhiteSpace([string]$nameProperty.Value)) {
                [string]$nameProperty.Value
            }
            else {
                Get-PackageNameFromSpec -Spec $spec
            }

            if (Test-Path -LiteralPath (Join-Path $ScoopRoot "apps\$name\current")) {
                $spec
            }
            else {
                Write-Host "跳过未安装的软件：$spec" -ForegroundColor DarkYellow
            }
        }
    )

    $appsToUpdate = @(
        $appsToUpdate |
            Sort-Object -Unique
    )

    if ($appsToUpdate.Count -gt 0) {
        # 不传 scoop；核心已经由 Bundle 的 scoop-core.zip 替换。
        Invoke-ScoopChildProcess -Arguments (@('update') + $appsToUpdate)
    }
    else {
        Write-Host 'Bundle 中对应的软件目前都未安装；只完成了 core / bucket / cache 更新。' -ForegroundColor Yellow
    }
}

# 成功后清理 staging，并按数量保留可回滚的 core/bucket 备份。
Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue

$backupParent = Join-Path $ScoopRoot 'offline-backups'
$backups = @(
    Get-ChildItem -LiteralPath $backupParent -Directory -Force -ErrorAction SilentlyContinue |
        Sort-Object CreationTimeUtc -Descending
)

if ($backups.Count -gt $KeepBackupCount) {
    $backups |
        Select-Object -Skip $KeepBackupCount |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
}

Write-Host "`n离线更新完成。" -ForegroundColor Green
Write-Host "Scoop 根目录：$ScoopRoot"
Write-Host "cache 目录：$CacheRoot"
Write-Host "已保留 core/bucket 备份数量：$KeepBackupCount"
Write-Host '请关闭并重新打开 PowerShell 后继续使用。' -ForegroundColor Green
