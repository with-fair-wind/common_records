[CmdletBinding()]
param(
    # 由外网 Build-ScoopOfflineBundle.ps1 生成并同步到内网的目录。
    [string]$BundleRoot = 'D:\ScoopOfflineBundle',

    # 内网 Scoop 根目录。首次部署应为空目录或不存在。
    [string]$ScoopRoot = 'D:\scoop',

    # 默认与 ScoopRoot\cache 相同。仅在需要将 cache 放到其他磁盘时指定。
    [string]$CacheRoot = '',

    # 仅用于清理首次安装失败残留；会删除整个 ScoopRoot。
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
    return $full
}

function Get-OSArchitecture {
    $raw = if ($env:PROCESSOR_ARCHITEW6432) {
        $env:PROCESSOR_ARCHITEW6432
    }
    else {
        $env:PROCESSOR_ARCHITECTURE
    }

    switch ($raw.ToUpperInvariant()) {
        'AMD64' { return '64bit' }
        'ARM64' { return 'arm64' }
        default { return '32bit' }
    }
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedHash
    )

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ine $ExpectedHash) {
        throw "SHA-256 校验失败：$Path"
    }
}

function Add-UserPathEntry {
    param([Parameter(Mandatory)][string]$PathEntry)

    $oldPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @(
        $oldPath -split ';' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $exists = @(
        $entries | Where-Object {
            $_.TrimEnd('\') -ieq $PathEntry.TrimEnd('\')
        }
    )

    if ($exists.Count -eq 0) {
        $newEntries = @($PathEntry) + $entries
        [Environment]::SetEnvironmentVariable('Path', ($newEntries -join ';'), 'User')
    }

    $processEntries = @(
        $env:Path -split ';' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $processHasEntry = @(
        $processEntries | Where-Object {
            $_.TrimEnd('\') -ieq $PathEntry.TrimEnd('\')
        }
    )

    if ($processHasEntry.Count -eq 0) {
        $env:Path = "$PathEntry;$env:Path"
    }
}

function New-ScoopBootstrapShims {
    param([Parameter(Mandatory)][string]$Root)

    $shimDir = Join-Path $Root 'shims'
    New-Item -ItemType Directory -Path $shimDir -Force | Out-Null

    # 仅用于首次引导。后续各应用的 shim 由 Scoop 自动生成。
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

    $psShim = @'
$target = Join-Path $PSScriptRoot '..\apps\scoop\current\bin\scoop.ps1'
& $target @args
exit $LASTEXITCODE
'@

    Set-Content -LiteralPath (Join-Path $shimDir 'scoop.cmd') -Value $cmdShim -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $shimDir 'scoop.ps1') -Value $psShim -Encoding UTF8
}

function Copy-VerifiedCacheFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][Int64]$Length,
        [Parameter(Mandatory)][string]$Sha256
    )

    if (Test-Path -LiteralPath $Destination) {
        $old = Get-Item -LiteralPath $Destination -Force
        if ($old.Length -eq $Length) {
            $oldHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
            if ($oldHash -ieq $Sha256) {
                return
            }
        }

        Remove-Item -LiteralPath $Destination -Force
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force

    $new = Get-Item -LiteralPath $Destination -Force
    if ($new.Length -ne $Length) {
        throw "复制后的 cache 文件大小不匹配：$(Split-Path $Destination -Leaf)"
    }

    Assert-Sha256 -Path $Destination -ExpectedHash $Sha256
}

function Invoke-Scoop {
    param([Parameter(Mandatory)][string[]]$Arguments)

    Write-Host ">> scoop $($Arguments -join ' ')" -ForegroundColor Cyan
    & $script:ScoopPs1 @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Scoop 命令失败，退出码：$LASTEXITCODE"
    }
}

$BundleRoot = Resolve-FullPath $BundleRoot
$ScoopRoot = Resolve-FullPath $ScoopRoot

$metadataPath = Join-Path $BundleRoot 'bundle.json'
$coreZip = Join-Path $BundleRoot 'scoop-core.zip'
$bucketsZip = Join-Path $BundleRoot 'buckets.zip'
$bundleCache = Join-Path $BundleRoot 'cache'

foreach ($required in @($metadataPath, $coreZip, $bucketsZip, $bundleCache)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "离线 Bundle 不完整，缺少：$required"
    }
}

$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json

$formatVersion = [int]$metadata.FormatVersion
if ($formatVersion -notin @(1, 2)) {
    throw "不支持的 Bundle 格式版本：$($metadata.FormatVersion)"
}

if ([string]$metadata.Architecture -ne (Get-OSArchitecture)) {
    throw "离线 Bundle 架构为 $($metadata.Architecture)，当前机器为 $(Get-OSArchitecture)，不能混用。"
}

Assert-Sha256 -Path $coreZip -ExpectedHash ([string]$metadata.ScoopCoreSha256)
Assert-Sha256 -Path $bucketsZip -ExpectedHash ([string]$metadata.BucketsSha256)

if (Test-Path -LiteralPath $ScoopRoot) {
    $existing = @(Get-ChildItem -LiteralPath $ScoopRoot -Force)
    if ($existing.Count -gt 0) {
        if (-not $Force) {
            throw @"
目标目录不是空目录：
$ScoopRoot

这是首次部署脚本。若该目录是之前失败留下的半成品，可确认无保留价值后增加 -Force 重试。
后续更新请使用 Update-ScoopOfflineBundle.ps1，不要运行本脚本。
"@
        }

        Remove-Item -LiteralPath $ScoopRoot -Recurse -Force
    }
}

if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    $CacheRoot = Join-Path $ScoopRoot 'cache'
}
$CacheRoot = Resolve-FullPath ([Environment]::ExpandEnvironmentVariables($CacheRoot))

New-Item -ItemType Directory -Path $ScoopRoot -Force | Out-Null

# 1. 部署 Scoop 核心和完整 main/extras bucket。
Expand-Archive -LiteralPath $coreZip -DestinationPath $ScoopRoot -Force
Expand-Archive -LiteralPath $bucketsZip -DestinationPath (Join-Path $ScoopRoot 'buckets') -Force

$script:ScoopPs1 = Join-Path $ScoopRoot 'apps\scoop\current\bin\scoop.ps1'
if (-not (Test-Path -LiteralPath $script:ScoopPs1)) {
    throw "解压后找不到 Scoop 主脚本：$script:ScoopPs1"
}

$bundledBucketsProperty = $metadata.PSObject.Properties['BundledBuckets']
$requiredBuckets = if ($null -ne $bundledBucketsProperty) {
    @(
        @($bundledBucketsProperty.Value) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}
else {
    @('main', 'extras')
}

if ($requiredBuckets.Count -eq 0) {
    throw 'bundle.json 中 BundledBuckets 为空。'
}

foreach ($bucket in $requiredBuckets) {
    $bucketDir = Join-Path $ScoopRoot "buckets\$bucket\bucket"
    if (-not (Test-Path -LiteralPath $bucketDir)) {
        throw "解压后的 bucket 不完整：$bucketDir"
    }
}

# 2. 拷贝 bundle 中的 cache 到 Scoop cache，并做逐文件长度 + SHA-256 校验。
New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null

$cacheInfos = @($metadata.CacheFiles)
if ($cacheInfos.Count -eq 0) {
    throw 'bundle.json 中没有 CacheFiles。'
}

foreach ($cacheInfo in $cacheInfos) {
    $source = Join-Path $bundleCache ([string]$cacheInfo.Name)
    $destination = Join-Path $CacheRoot ([string]$cacheInfo.Name)

    if (-not (Test-Path -LiteralPath $source)) {
        throw "Bundle 缺少 cache 文件：$($cacheInfo.Name)"
    }

    $sourceInfo = Get-Item -LiteralPath $source -Force
    if ($sourceInfo.Length -ne [Int64]$cacheInfo.Length) {
        throw "Bundle cache 文件大小不匹配：$($cacheInfo.Name)"
    }

    Assert-Sha256 -Path $source -ExpectedHash ([string]$cacheInfo.Sha256)
    Copy-VerifiedCacheFile `
        -Source $source `
        -Destination $destination `
        -Length ([Int64]$cacheInfo.Length) `
        -Sha256 ([string]$cacheInfo.Sha256)
}

# 3. 设置当前用户环境。SCOOP_CACHE 可选，但使用它能保证 Scoop 与本脚本使用同一 cache。
$env:SCOOP = $ScoopRoot
$env:SCOOP_CACHE = $CacheRoot

[Environment]::SetEnvironmentVariable('SCOOP', $ScoopRoot, 'User')
[Environment]::SetEnvironmentVariable('SCOOP_CACHE', $CacheRoot, 'User')

New-ScoopBootstrapShims -Root $ScoopRoot
Add-UserPathEntry -PathEntry (Join-Path $ScoopRoot 'shims')

# 将 last_update 设为当前时间，避免 install 时尝试在内网执行 Scoop / bucket 的 Git 同步。
Invoke-Scoop -Arguments @('config', 'last_update', (Get-Date).ToString('o'))

# 4. 从本地 cache 首先安装 7zip（供 .7z / MSI 解压），再安装 bundle 中的请求软件。
$requested = @($metadata.RequestedPackages | ForEach-Object { [string]$_ })
if ($requested.Count -eq 0) {
    throw 'bundle.json 中没有 RequestedPackages。'
}

if ($requested -contains '7zip') {
    Invoke-Scoop -Arguments @('install', '--no-update-scoop', '7zip')
}

$remaining = @($requested | Where-Object { $_ -ne '7zip' })
if ($remaining.Count -gt 0) {
    Invoke-Scoop -Arguments (@('install', '--no-update-scoop') + $remaining)
}

Write-Host "`n首次离线安装完成。" -ForegroundColor Green
Write-Host '请关闭并重新打开 PowerShell，再使用 scoop / code / clangd 等命令。' -ForegroundColor Green
