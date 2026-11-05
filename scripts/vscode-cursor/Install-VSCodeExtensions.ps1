<#
.SYNOPSIS
按离线清单镜像同步 VS Code 用户扩展，卸载内网额外扩展。
.DESCRIPTION
安装前校验全部包的 ID、版本、平台和 SHA-256，拒绝未完成的导出。
同版本跳过，其他版本用本地 VSIX 覆盖（包括降级），不从清单外的 VSIX 推断目标。
目标版本全部安装并核对成功后，才卸载清单之外的用户扩展；最后核对集合和版本。
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$BundleDir = $PSScriptRoot,
    [string]$CodeCmd = 'code',
    [string]$ProfileName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'VSCodeExtensions.Common.ps1')

$BundleDir = (Resolve-Path -LiteralPath $BundleDir).Path
$manifestPath = Join-Path $BundleDir 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
if ($manifest -isnot [System.Collections.IDictionary] -or $manifest.schemaVersion -ne 1 -or $manifest.complete -isnot [bool] -or -not $manifest.complete) {
    throw '离线清单格式不受支持或导出未完成；请在外网重新导出完整同步包。'
}
if ($manifest.extensions -isnot [array]) { throw '离线清单没有有效的扩展数组。' }
$vsixDir = Join-Path $BundleDir 'vsix'
Assert-VsixDirectory -Directory $vsixDir
if (-not (Test-Path -LiteralPath $vsixDir -PathType Container)) { throw "找不到 VSIX 目录：$vsixDir" }

$seen = @{}
$targets = @($manifest.extensions)
# 全量预检后才调用 VS Code，缺包或文件损坏时不产生部分安装。
foreach ($entry in $targets) {
    if ($entry -isnot [System.Collections.IDictionary]) { throw '清单包含无效扩展记录。' }
    Assert-ExtensionIdentity $entry
    if ($seen.ContainsKey($entry.id)) { throw "清单包含重复扩展：$($entry.id)" }
    $seen[$entry.id] = $true
    $expectedFile = "$($entry.id)-$($entry.version)-$($entry.targetPlatform).vsix"
    if ($entry.status -ne 'ready' -or $entry.file -cne $expectedFile -or $entry.sha256 -notmatch '^[a-f0-9]{64}$') {
        throw "扩展记录未就绪或文件名 / SHA-256 无效：$($entry.id)"
    }
    $packagePath = Join-Path (Join-Path $BundleDir 'vsix') $entry.file
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw "离线包缺失：$packagePath" }
    if ((Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash -ne $entry.sha256) { throw "SHA-256 校验失败：$packagePath" }
    Assert-VsixPackage -Path $packagePath -Extension $entry
}

$scopeArguments = @()
if ($ProfileName) { $scopeArguments = @('--profile', $ProfileName) }
$installed = Get-VSCodeInstalledVersion -CodeCmd $CodeCmd -ScopeArguments $scopeArguments
$failed = [Collections.Generic.List[string]]::new()
$installedCount = 0
$skippedCount = 0
foreach ($entry in $targets) {
    if ($installed[$entry.id] -ceq $entry.version) {
        $skippedCount++
        Write-Host "跳过同版本 $($entry.id)@$($entry.version)"
        continue
    }
    $packagePath = Join-Path (Join-Path $BundleDir 'vsix') $entry.file
    try {
        # 快照中的依赖由本地包提供，禁止安装扩展包时自动从 Marketplace 补依赖。
        $arguments = @('--install-extension', $packagePath, '--force', '--do-not-include-pack-dependencies') + $scopeArguments
        $output = @(Invoke-VSCodeCli -CodeCmd $CodeCmd -ArgumentList $arguments)
        Write-Verbose ($output -join [Environment]::NewLine)
        $installedCount++
        Write-Host "已安装 $($entry.id)@$($entry.version)" -ForegroundColor Green
    }
    catch {
        $failed.Add($entry.id)
        Write-Warning "安装失败 $($entry.id)：$_"
    }
}

# CLI 返回成功也需核对最终版本，防止实际未安装或仍保留了不同版本。
$actual = Get-VSCodeInstalledVersion -CodeCmd $CodeCmd -ScopeArguments $scopeArguments
foreach ($entry in $targets) {
    if ($actual[$entry.id] -cne $entry.version -and -not $failed.Contains($entry.id)) {
        $failed.Add($entry.id)
        Write-Warning "最终版本不匹配：$($entry.id)，期望 $($entry.version)，实际 $($actual[$entry.id])"
    }
}
if ($failed.Count -gt 0) {
    throw "以下扩展同步失败：$($failed -join ', ')。未执行额外扩展卸载；修复后可重跑。"
}

# 只在全部目标版本核对一致后卸载额外扩展，避免安装失败时进一步改变环境。
$extras = @($actual.Keys | Where-Object { -not $seen.ContainsKey($_) } | Sort-Object)
$uninstalledCount = 0
if ($extras.Count -gt 0) {
    $pending = @($extras)
    $uninstallErrors = @{}
    do {
        $previousCount = $pending.Count
        foreach ($id in $pending) {
            try {
                $arguments = @('--uninstall-extension', $id, '--force') + $scopeArguments
                $output = @(Invoke-VSCodeCli -CodeCmd $CodeCmd -ArgumentList $arguments)
                Write-Verbose ($output -join [Environment]::NewLine)
                $uninstalledCount++
                Write-Host "已卸载清单外扩展 $id" -ForegroundColor Yellow
            }
            catch { $uninstallErrors[$id] = $_.Exception.Message }
        }
        $actual = Get-VSCodeInstalledVersion -CodeCmd $CodeCmd -ScopeArguments $scopeArguments
        $pending = @($extras | Where-Object { $actual.ContainsKey($_) })
        # 一轮有实际进展才重试，以处理“先卸载依赖者，再卸载依赖”的顺序约束。
    } while ($pending.Count -gt 0 -and $pending.Count -lt $previousCount)
    foreach ($id in $pending) {
        $failed.Add($id)
        Write-Warning "清单外扩展卸载未完成 $($id)：$($uninstallErrors[$id])"
    }

    # VS Code 卸载扩展包可能连带移除包内扩展；从本地 VSIX 恢复仍在目标清单中的扩展。
    $restoreTargets = @($targets | Where-Object { $actual[$_.id] -cne $_.version })
    foreach ($entry in $restoreTargets) {
        try {
            $packagePath = Join-Path $vsixDir $entry.file
            $arguments = @('--install-extension', $packagePath, '--force', '--do-not-include-pack-dependencies') + $scopeArguments
            $output = @(Invoke-VSCodeCli -CodeCmd $CodeCmd -ArgumentList $arguments)
            Write-Verbose ($output -join [Environment]::NewLine)
            $installedCount++
            Write-Host "已恢复清单中的扩展 $($entry.id)@$($entry.version)" -ForegroundColor Green
        }
        catch {
            $failed.Add($entry.id)
            Write-Warning "恢复清单扩展失败 $($entry.id)：$_"
        }
    }
    if ($restoreTargets.Count -gt 0) {
        $actual = Get-VSCodeInstalledVersion -CodeCmd $CodeCmd -ScopeArguments $scopeArguments
    }
    foreach ($entry in $targets) {
        if ($actual[$entry.id] -cne $entry.version -and -not $failed.Contains($entry.id)) {
            $failed.Add($entry.id)
            Write-Warning "卸载后的目标版本不匹配：$($entry.id)"
        }
    }
    foreach ($id in $actual.Keys) {
        if (-not $seen.ContainsKey($id) -and -not $failed.Contains($id)) {
            $failed.Add($id)
            Write-Warning "清单外扩展仍然存在：$id"
        }
    }
}
Write-Host "同步结束：安装命令成功 $installedCount，跳过 $skippedCount，卸载命令成功 $uninstalledCount，失败 $($failed.Count)。"
if ($failed.Count -gt 0) { throw "以下扩展镜像同步失败：$($failed -join ', ')。修复后可重跑。" }
try {
    $removed = Remove-UnreferencedVsixPackage -Directory $vsixDir -KeepFileNames @($targets | ForEach-Object { $_.file })
}
catch { throw "用户扩展已对齐，但离线目录旧包清理失败：$_" }
Write-Host "已清理离线目录中 $removed 个未引用的包或下载临时文件。"
Write-Host '用户扩展集合及版本均已与外网清单核对一致。' -ForegroundColor Green
