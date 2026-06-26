# 批量安装 VS Code / Cursor 扩展（按清单或 VSIX 目录）
# 使用示例：
#   .\Install-VSCodeExtensions.ps1 -Mode vscode -Source list
#   .\Install-VSCodeExtensions.ps1 -Mode cursor -Source list -CodeCmd cursor
#   .\Install-VSCodeExtensions.ps1 -Mode vscode -Source vsix
#   .\Install-VSCodeExtensions.ps1 -Mode cursor -Source vsix -VsixDir .\vsix\cursor

[CmdletBinding()]
param (
    [ValidateSet("cursor", "vscode")]
    [string]$Mode = "vscode",
    [ValidateSet("list", "vsix")]
    [string]$Source = "list",
    [string]$ListPath,
    [string]$VsixDir,
    [string]$CodeCmd
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $CodeCmd) {
    $CodeCmd = if ($Mode -eq "cursor") { "cursor" } else { "code" }
}

if ($Source -eq "list") {
    if (-not $ListPath) {
        $ListPath = Join-Path $ScriptDir "extensions-$Mode.txt"
    }

    if (-not (Test-Path $ListPath)) {
        throw "找不到扩展清单：$ListPath"
    }

    $targets = Get-Content $ListPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") } |
        Select-Object -Unique

    if (-not $targets -or $targets.Count -eq 0) {
        throw "扩展清单为空：$ListPath"
    }

    Write-Host "📄 扩展清单: $ListPath" -ForegroundColor Cyan
}
else {
    if (-not $VsixDir) {
        $VsixDir = Join-Path (Join-Path $ScriptDir "vsix") $Mode
    }

    if (-not (Test-Path $VsixDir)) {
        throw "找不到 VSIX 目录：$VsixDir"
    }

    $targets = Get-ChildItem -Path $VsixDir -Filter "*.vsix" -File |
        Sort-Object Name |
        ForEach-Object { $_.FullName }

    if (-not $targets -or $targets.Count -eq 0) {
        throw "VSIX 目录下没有可安装文件：$VsixDir"
    }

    Write-Host "📦 VSIX 目录: $VsixDir" -ForegroundColor Cyan
}

$total = $targets.Count
$failed = [System.Collections.ArrayList]::new()

Write-Host "🧭 安装来源: $Source" -ForegroundColor Cyan
Write-Host "🔧 安装命令: $CodeCmd" -ForegroundColor Cyan
Write-Host "共 $total 个扩展，开始安装..." -ForegroundColor Cyan

for ($i = 0; $i -lt $total; $i++) {
    $target = $targets[$i]
    $n = $i + 1
    $displayName = if ($Source -eq "list") { $target } else { Split-Path -Leaf $target }

    Write-Host "[$n/$total] $displayName" -NoNewline
    try {
        & $CodeCmd --install-extension $target 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            [void]$failed.Add($displayName)
            Write-Host " 失败" -ForegroundColor Red
        } else {
            Write-Host " 完成" -ForegroundColor Green
        }
    } catch {
        [void]$failed.Add($displayName)
        Write-Host " 失败: $_" -ForegroundColor Red
    }
}

if ($failed.Count -gt 0) {
    Write-Host "`n以下扩展安装失败 ($($failed.Count) 个):" -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Host "  - $_" }
} else {
    Write-Host "`n全部 $total 个扩展已安装完成。" -ForegroundColor Green
}
