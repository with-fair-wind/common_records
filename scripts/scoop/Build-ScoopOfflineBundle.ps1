[CmdletBinding()]
param(
    # 外网机器 Scoop 根目录。
    [string]$ScoopRoot = 'D:\scoop',

    # 生成并供内网同步的离线 Bundle 目录。
    [string]$BundleRoot = 'D:\ScoopOfflineBundle',

    # Scoop cache 不在 <ScoopRoot>\cache 时显式指定；默认自动探测。
    [string]$CacheRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)

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

function Assert-RobocopySuccess {
    param([Parameter(Mandatory)][string]$Description)

    # Robocopy 的 0~7 都是成功、已复制或存在差异；>= 8 才表示失败。
    if ($LASTEXITCODE -ge 8) {
        throw "$Description 失败，Robocopy 退出码：$LASTEXITCODE"
    }
}

function Copy-DirectoryTree {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "源目录不存在：$Source"
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    $robocopyArguments = @(
        $Source,
        $Destination,
        '/E',
        '/XJ',       # 不跟随 Junction，避免把 current 当作普通目录复制。
        '/XD', '.git',
        '/COPY:DAT',
        '/DCOPY:DAT',
        '/R:1',
        '/W:1',
        '/NFL',
        '/NDL',
        '/NP'
    )

    & robocopy @robocopyArguments
    Assert-RobocopySuccess "复制目录：$Source"
}

function Get-PackageParts {
    param([Parameter(Mandatory)][string]$PackageSpec)

    $value = $PackageSpec.Trim().Replace('\', '/')

    if ($value -match '^(?<Bucket>[^/]+)/(?<Name>[^/]+)$') {
        return [PSCustomObject]@{
            Bucket = $Matches.Bucket
            Name   = $Matches.Name
        }
    }

    if ($value -match '^[^/]+$') {
        return [PSCustomObject]@{
            Bucket = 'main'
            Name   = $value
        }
    }

    throw "无法识别 Scoop 包标识：$PackageSpec"
}

function Get-CanonicalPackageSpec {
    param([Parameter(Mandatory)][PSCustomObject]$Package)

    if ($Package.Bucket -eq 'main') {
        return [string]$Package.Name
    }

    return "$($Package.Bucket)/$($Package.Name)"
}

function Add-HardLinkOrCopy {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $sourceDrive = [System.IO.Path]::GetPathRoot($Source)
    $destinationDrive = [System.IO.Path]::GetPathRoot($Destination)

    if ($sourceDrive -ieq $destinationDrive) {
        try {
            New-Item -ItemType HardLink -Path $Destination -Target $Source -ErrorAction Stop |
                Out-Null
            return
        }
        catch {
            Write-Warning "无法建立硬链接，改为实际复制：$(Split-Path -Path $Source -Leaf)"
        }
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

$ScoopRoot = Resolve-FullPath $ScoopRoot
$BundleRoot = Resolve-FullPath $BundleRoot

if ($ScoopRoot -eq $BundleRoot) {
    throw 'ScoopRoot 与 BundleRoot 不能相同。'
}

if ($BundleRoot.StartsWith("$ScoopRoot\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'BundleRoot 不能位于 ScoopRoot 内部。'
}

$scoopCurrent = Join-Path $ScoopRoot 'apps\scoop\current'
$scoopPs1 = Join-Path $scoopCurrent 'bin\scoop.ps1'

if (-not (Test-Path -LiteralPath $scoopPs1)) {
    throw "找不到 Scoop 主脚本：$scoopPs1"
}

if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    $CacheRoot = if ($env:SCOOP_CACHE) {
        $env:SCOOP_CACHE
    }
    else {
        Join-Path $ScoopRoot 'cache'
    }
}

$CacheRoot = Resolve-FullPath ([Environment]::ExpandEnvironmentVariables($CacheRoot))

if (-not (Test-Path -LiteralPath $CacheRoot)) {
    throw "找不到 Scoop cache 目录：$CacheRoot"
}

$env:SCOOP = $ScoopRoot
$env:SCOOP_CACHE = $CacheRoot

# 修改此数组即可扩展内网软件集。
# 这里显式包含 7zip：它是 LLVM、VS Code、Windows Terminal 等压缩包的常用解压工具。
$RequestedPackages = @(
    '7zip',
    'clangd',
    'cmake',
    'ninja',
    'llvm',
    'extras/vscode',
    'extras/windows-terminal',
    'versions/windows-terminal-preview'
)

# 递归通过 `scoop depends` 计算明确依赖闭包。
# suggested 依赖不会被自动安装，因此不会在这里被打包。
$queue = [System.Collections.Generic.Queue[string]]::new()
$seen = @{}
$downloadSpecs = [System.Collections.Generic.List[string]]::new()

foreach ($spec in $RequestedPackages) {
    $queue.Enqueue($spec)
}

while ($queue.Count -gt 0) {
    $rawSpec = $queue.Dequeue()
    $parts = Get-PackageParts $rawSpec
    $canonicalSpec = Get-CanonicalPackageSpec $parts
    $key = $canonicalSpec.ToLowerInvariant()

    if ($seen.ContainsKey($key)) {
        continue
    }

    $manifestPath = Join-Path $ScoopRoot "buckets\$($parts.Bucket)\bucket\$($parts.Name).json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "找不到 manifest：$manifestPath。请确认外网 Scoop 已添加 bucket '$($parts.Bucket)'。"
    }

    $seen[$key] = $true
    $downloadSpecs.Add($canonicalSpec)

    Write-Host "解析依赖：$canonicalSpec" -ForegroundColor Cyan
    $dependencies = @(& $scoopPs1 depends $canonicalSpec)

    if ($LASTEXITCODE -ne 0) {
        throw "解析依赖失败：$canonicalSpec"
    }

    foreach ($dependency in $dependencies) {
        $nameProperty = $dependency.PSObject.Properties['Name']
        if ($null -eq $nameProperty) {
            continue
        }

        $dependencyName = [string]$nameProperty.Value
        if ([string]::IsNullOrWhiteSpace($dependencyName)) {
            continue
        }

        $sourceProperty = $dependency.PSObject.Properties['Source']
        $dependencySource = if ($null -ne $sourceProperty) {
            [string]$sourceProperty.Value
        }
        else {
            'main'
        }

        if ($dependencySource -match '^[a-zA-Z]+://') {
            throw "发现 URL 形式依赖，当前离线流程不支持自动打包：$dependencySource"
        }

        $dependencySpec = if (
            [string]::IsNullOrWhiteSpace($dependencySource) -or
            $dependencySource -eq 'main'
        ) {
            $dependencyName
        }
        else {
            "$dependencySource/$dependencyName"
        }

        $queue.Enqueue($dependencySpec)
    }
}

Write-Host "`n将下载到离线 Bundle 的软件：" -ForegroundColor Yellow
$downloadSpecs | ForEach-Object { Write-Host "  $_" }

# 只下载到 cache，不安装；即使 Scoop 本体检测到更新，也不在此处自动更新它。
& $scoopPs1 download --no-update-scoop @downloadSpecs
if ($LASTEXITCODE -ne 0) {
    throw "scoop download 失败，退出码：$LASTEXITCODE"
}

$cacheInventory = @(Get-ChildItem -LiteralPath $CacheRoot -File -Force)
$packageDetails = [System.Collections.Generic.List[object]]::new()
$selectedCacheFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

foreach ($spec in $downloadSpecs) {
    $parts = Get-PackageParts $spec
    $manifestPath = Join-Path $ScoopRoot "buckets\$($parts.Bucket)\bucket\$($parts.Name).json"
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $version = [string]$manifest.version

    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "manifest 缺少 version：$manifestPath"
    }

    # Scoop 的 cache 文件名始终以 app#version# 开头；末段随 Scoop 版本可能是 URL 文本或 URL 哈希。
    $cachePrefix = "$($parts.Name)#$version#"
    $matches = @(
        $cacheInventory | Where-Object {
            $_.Name.StartsWith($cachePrefix, [System.StringComparison]::OrdinalIgnoreCase)
        }
    )

    if ($matches.Count -eq 0) {
        throw "未找到 cache 文件：$spec ($version)"
    }

    $packageDetails.Add([PSCustomObject]@{
        Spec       = $spec
        Bucket     = $parts.Bucket
        Name       = $parts.Name
        Version    = $version
        CacheFiles = @($matches.Name)
    })

    foreach ($match in $matches) {
        $selectedCacheFiles.Add($match)
    }
}

$selectedCacheFiles = @(
    $selectedCacheFiles |
        Sort-Object FullName -Unique
)

$bundledBuckets = @(
    $packageDetails |
        Select-Object -ExpandProperty Bucket -Unique |
        Sort-Object
)

$buildRoot = "$BundleRoot.__building"
$backupRoot = "$BundleRoot.__previous"

Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue

$coreStage = Join-Path $buildRoot 'stage-core'
$bucketStage = Join-Path $buildRoot 'stage-buckets'
$bundleCache = Join-Path $buildRoot 'cache'

New-Item -ItemType Directory -Path @($coreStage, $bucketStage, $bundleCache) -Force |
    Out-Null

# Scoop 自身位于 apps\scoop\current 的真实目录，不是普通应用的 version + current Junction 结构。
Copy-DirectoryTree `
    -Source $scoopCurrent `
    -Destination (Join-Path $coreStage 'apps\scoop\current')

$coreZip = Join-Path $buildRoot 'scoop-core.zip'
Push-Location $coreStage
try {
    Compress-Archive -Path 'apps' -DestinationPath $coreZip -CompressionLevel Fastest -Force
}
finally {
    Pop-Location
}

# 为离线 search / install 复制完整 bucket（排除 .git），并自动包含 main、extras、versions 等实际涉及的 bucket。
foreach ($bucket in $bundledBuckets) {
    Copy-DirectoryTree `
        -Source (Join-Path $ScoopRoot "buckets\$bucket") `
        -Destination (Join-Path $bucketStage $bucket)
}

$bucketsZip = Join-Path $buildRoot 'buckets.zip'
Push-Location $bucketStage
try {
    Compress-Archive -Path $bundledBuckets -DestinationPath $bucketsZip -CompressionLevel Fastest -Force
}
finally {
    Pop-Location
}

# 尽量创建硬链接，避免外网机再占一份大型下载包；跨网同步时它们仍表现为普通文件。
foreach ($cacheFile in $selectedCacheFiles) {
    Add-HardLinkOrCopy `
        -Source $cacheFile.FullName `
        -Destination (Join-Path $bundleCache $cacheFile.Name)
}

$cacheMetadata = @(
    foreach ($cacheFile in $selectedCacheFiles) {
        [PSCustomObject]@{
            Name   = $cacheFile.Name
            Length = [int64]$cacheFile.Length
            Sha256 = (Get-FileHash -LiteralPath $cacheFile.FullName -Algorithm SHA256).Hash
        }
    }
)

$metadata = [ordered]@{
    FormatVersion      = 2
    CreatedAt          = (Get-Date).ToString('o')
    Architecture       = Get-OSArchitecture
    RequestedPackages  = @($RequestedPackages)
    DownloadedPackages = @($packageDetails)
    BundledBuckets     = @($bundledBuckets)
    CacheFiles         = @($cacheMetadata)
    ScoopCoreSha256    = (Get-FileHash -LiteralPath $coreZip -Algorithm SHA256).Hash
    BucketsSha256      = (Get-FileHash -LiteralPath $bucketsZip -Algorithm SHA256).Hash
}

$metadata |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $buildRoot 'bundle.json') -Encoding UTF8

@(
    'Scoop Offline Bundle'
    ''
    "CreatedAt: $($metadata.CreatedAt)"
    "Architecture: $($metadata.Architecture)"
    "Buckets: $($bundledBuckets -join ', ')"
    ''
    'Requested packages:'
    $RequestedPackages
    ''
    'On a new intranet computer, run Install-ScoopOfflineBundle.ps1.'
    'On an already deployed intranet computer, run Update-ScoopOfflineBundle.ps1 first.'
) |
    Set-Content -LiteralPath (Join-Path $buildRoot 'README.txt') -Encoding UTF8

# stage-core / stage-buckets 仅用于构建 zip；
# 最终 Bundle 只保留压缩包、cache 与元数据，避免跨网同步大量小文件。
Remove-Item -LiteralPath $coreStage -Recurse -Force
Remove-Item -LiteralPath $bucketStage -Recurse -Force

# 原子替换：Bundle 仅在构建完整成功后才替换旧版本。
try {
    if (Test-Path -LiteralPath $BundleRoot) {
        Move-Item -LiteralPath $BundleRoot -Destination $backupRoot
    }

    Move-Item -LiteralPath $buildRoot -Destination $BundleRoot
    Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    if (-not (Test-Path -LiteralPath $BundleRoot) -and (Test-Path -LiteralPath $backupRoot)) {
        Move-Item -LiteralPath $backupRoot -Destination $BundleRoot
    }

    throw
}

$bundleSize = (
    Get-ChildItem -LiteralPath $BundleRoot -Recurse -File |
        Measure-Object -Property Length -Sum
).Sum

Write-Host "`n离线 Bundle 已生成。" -ForegroundColor Green
Write-Host "目录：$BundleRoot"
Write-Host ("总大小：{0:N2} GB" -f ($bundleSize / 1GB))
Write-Host "Bucket：$($bundledBuckets -join ', ')"
Write-Host "Cache 文件数：$($selectedCacheFiles.Count)"
