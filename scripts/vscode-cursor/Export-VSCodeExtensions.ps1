<#
.SYNOPSIS
将外网 VS Code 已安装扩展导出为固定版本的离线同步包。
.DESCRIPTION
读取 extensions.json 的 ID、版本和平台，下载对应 VSIX 并生成带 SHA-256 的 manifest.json。
不自动更新扩展。缺包会保存 complete=false 的清单并抛错；重跑可复用已校验的包。
所有目标包就绪后自动删除清单未引用的旧 VSIX，使离线包集合与外网快照一致。
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$JsonPath,
    [string]$OutputDir = (Join-Path $PSScriptRoot 'offline-bundle'),
    [ValidateRange(0, 10)][int]$RetryCount = 2,
    [ValidateRange(0, 60)][int]$RetryDelaySeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'VSCodeExtensions.Common.ps1')

if (-not $JsonPath) {
    $candidates = @(
        $(if ($env:VSCODE_EXTENSIONS) { Join-Path $env:VSCODE_EXTENSIONS 'extensions.json' }),
        'D:\scoop\apps\vscode\current\data\extensions\extensions.json',
        (Join-Path $env:USERPROFILE '.vscode\extensions\extensions.json')
    ) | Where-Object { $_ }
    $JsonPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $JsonPath) { throw "找不到 extensions.json，请用 -JsonPath 指定。已尝试：$($candidates -join ', ')" }
}
$JsonPath = (Resolve-Path -LiteralPath $JsonPath).Path
$source = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate
if ($source -isnot [array]) {
    throw 'extensions.json 必须是已安装扩展数组，不能使用工作区 .vscode/extensions.json。'
}

$extensions = [Collections.Generic.List[object]]::new()
$seen = @{}
foreach ($item in $source) {
    if ($item -isnot [System.Collections.IDictionary] -or $item.identifier -isnot [System.Collections.IDictionary]) {
        throw 'extensions.json 中存在无效的扩展记录。'
    }
    $metadata = $item['metadata']
    $platform = if ($metadata -is [System.Collections.IDictionary]) { [string]$metadata['targetPlatform'] } else { '' }
    $entry = [ordered]@{
        id = [string]$item.identifier.id
        version = [string]$item.version
        targetPlatform = Get-NormalizedTargetPlatform $platform
        file = ''
        sha256 = ''
        status = 'pending'
        error = $null
    }
    Assert-ExtensionIdentity $entry
    $entry.id = $entry.id.ToLowerInvariant()
    if ($seen.ContainsKey($entry.id)) {
        if ($seen[$entry.id] -ne "$($entry.version)/$($entry.targetPlatform)") {
            throw "同一扩展存在不同版本或平台，无法确定同步目标：$($entry.id)"
        }
        continue
    }
    $seen[$entry.id] = "$($entry.version)/$($entry.targetPlatform)"
    $entry.file = "$($entry.id)-$($entry.version)-$($entry.targetPlatform).vsix"
    $extensions.Add($entry)
}

$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$vsixDir = Join-Path $OutputDir 'vsix'
Assert-VsixDirectory -Directory $vsixDir
New-Item -ItemType Directory -Path $vsixDir -Force | Out-Null
$manifestPath = Join-Path $OutputDir 'manifest.json'
$oldHashes = @{}
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $previous = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
        foreach ($entry in $previous.extensions) {
            if ($entry.status -eq 'ready' -and $entry.sha256 -match '^[a-f0-9]{64}$') { $oldHashes[$entry.file] = $entry.sha256 }
        }
    }
    catch { Write-Warning "旧清单无法读取，将重新下载：$_" }
}

$manifest = [ordered]@{
    schemaVersion = 1
    exportedAtUtc = [DateTime]::UtcNow.ToString('o')
    complete = $false
    extensions = @($extensions | Sort-Object { $_.id })
}
# 先撤销旧清单的完成标记，防止中断后将新旧两批包误认成完整同步包。
Write-BundleManifest -Manifest $manifest -Path $manifestPath
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-VSCodeExtensions.ps1') -Destination $OutputDir -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'VSCodeExtensions.Common.ps1') -Destination $OutputDir -Force

foreach ($entry in $manifest.extensions) {
    $packagePath = Join-Path $vsixDir $entry.file
    $temporaryPath = "$packagePath.$([guid]::NewGuid().ToString('N')).partial"
    Write-Host "导出 $($entry.id)@$($entry.version) [$($entry.targetPlatform)]"
    try {
        $reuse = $false
        if ((Test-Path -LiteralPath $packagePath -PathType Leaf) -and $oldHashes.ContainsKey($entry.file)) {
            try {
                Assert-VsixPackage -Path $packagePath -Extension $entry
                $reuse = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash -eq $oldHashes[$entry.file]
            }
            catch { Write-Warning "本地包校验失败，将重新下载：$($entry.file)" }
        }
        if (-not $reuse) {
            $publisher, $name = $entry.id -split '\.', 2
            $url = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$publisher/vsextensions/$name/$($entry.version)/vspackage"
            if ($entry.targetPlatform -ne 'universal') { $url += "?targetPlatform=$($entry.targetPlatform)" }
            for ($attempt = 0; $attempt -le $RetryCount; $attempt++) {
                try {
                    Invoke-WebRequest -Uri $url -OutFile $temporaryPath -TimeoutSec 120
                    Assert-VsixPackage -Path $temporaryPath -Extension $entry
                    [IO.File]::Move($temporaryPath, $packagePath, $true)
                    break
                }
                catch {
                    if ($attempt -eq $RetryCount) { throw }
                    Start-Sleep -Seconds $RetryDelaySeconds
                }
            }
        }
        $entry.sha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry.status = 'ready'
        Write-Host $(if ($reuse) { '  已校验，复用离线包' } else { '  下载并校验完成' }) -ForegroundColor Green
    }
    catch {
        $entry.status = 'failed'
        $entry.error = $_.Exception.Message
        Write-Warning "导出失败 $($entry.id)：$($entry.error)"
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
    Write-BundleManifest -Manifest $manifest -Path $manifestPath
}

$failed = @($manifest.extensions | Where-Object { $_.status -ne 'ready' })
if ($failed.Count -gt 0) {
    throw "导出未完成：$($failed.Count)/$($manifest.extensions.Count) 个扩展失败。详见 $manifestPath；修复网络或扩展来源后重跑。"
}
# 新包全部就绪才清理，不因某个扩展下载失败而先删除可用旧包。
try {
    $removed = Remove-UnreferencedVsixPackage -Directory $vsixDir -KeepFileNames @($manifest.extensions | ForEach-Object { $_.file })
}
catch { throw "清理未引用的 VSIX 失败，导出仍标记为未完成：$_" }
$manifest.complete = $true
Write-BundleManifest -Manifest $manifest -Path $manifestPath
Write-Host "已清理 $removed 个未引用的包或下载临时文件。"
Write-Host "导出完成：$($manifest.extensions.Count) 个扩展。将整个目录复制到内网：$OutputDir" -ForegroundColor Green
