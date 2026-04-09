# ============================================================
# Download-VSCodeExtensions.ps1
# - Cursor / VS Code 分目录下载
# - 默认 Cursor 模式
# - 支持从 txt 或 extensions.json
# ============================================================

[CmdletBinding()]
param (
    [ValidateSet("cursor", "vscode", "json")]
    [string]$Mode = "cursor",
    [string]$JsonPath,
    [switch]$PruneOldVersions
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# 路径定义
# ------------------------------------------------------------

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$VsixRoot  = Join-Path $ScriptDir "vsix"
$OutDir    = Join-Path $VsixRoot $Mode   # ⭐ 关键：按模式分目录

$CursorList = Join-Path $ScriptDir "extensions-cursor.txt"
$VSCodeList = Join-Path $ScriptDir "extensions-vscode.txt"

$ApiUrl = "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery?api-version=7.1-preview.1"
$SleepSeconds = 2

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ------------------------------------------------------------
# Cursor 不支持的扩展规则
# ------------------------------------------------------------

$ExcludePatterns = @(
    '^github\.copilot',
    '^ms-vscode\.remote',
    '^ms-vscode-remote\.',
    '^ms-vscode\.vscode-typescript',
    '^ms-vscode\.js-debug',
    '^ms-vscode\.node-debug',
    '^ms-vscode\.powershell',
    '^ms-azuretools\.',
    '^ms-kubernetes-tools\.',
    '^ms-vsliveshare\.',
    '^visualstudioexptteam\.',
    '^ms-toolsai\.jupyter'
)

# ------------------------------------------------------------
# 扩展来源
# ------------------------------------------------------------

$DefaultJsonCandidates = @(
    "D:\scoop\apps\vscode\current\data\extensions\extensions.json",
    (Join-Path $env:USERPROFILE ".vscode\extensions\extensions.json")
)

function Resolve-ExtensionsJsonPath {
    if ($JsonPath) {
        if (Test-Path $JsonPath) {
            return $JsonPath
        }
        throw "找不到 extensions.json（-JsonPath）：$JsonPath"
    }

    foreach ($path in $DefaultJsonCandidates) {
        if (Test-Path $path) {
            return $path
        }
    }

    throw "找不到 extensions.json。已尝试路径：`n - $($DefaultJsonCandidates -join "`n - ")"
}

function Get-ExtensionsFromJson {
    $resolvedJsonPath = Resolve-ExtensionsJsonPath
    Write-Host "📄 使用 extensions.json：$resolvedJsonPath"

    (Get-Content $resolvedJsonPath -Raw | ConvertFrom-Json) |
        ForEach-Object { $_.identifier.id } |
        Sort-Object -Unique
}

function Get-ExtensionsFromTxt($Path) {
    if (!(Test-Path $Path)) {
        throw "找不到扩展列表：$Path"
    }
    Get-Content $Path | Where-Object { $_.Trim() }
}

function Filter-CursorExtensions($All) {
    foreach ($id in $All) {
        $blocked = $false
        foreach ($pattern in $ExcludePatterns) {
            if ($id -match $pattern) {
                $blocked = $true
                break
            }
        }
        if (-not $blocked) { $id }
    }
}

# ------------------------------------------------------------
# 根据模式选择扩展
# ------------------------------------------------------------

switch ($Mode) {
    "cursor" {
        if (Test-Path $CursorList) {
            Write-Host "📄 使用 Cursor 扩展清单：$CursorList"
            $Extensions = Get-ExtensionsFromTxt $CursorList
        } else {
            Write-Host "⚠️ 未找到 extensions-cursor.txt，自动从 JSON 筛选"
            $Extensions = Filter-CursorExtensions (Get-ExtensionsFromJson)
        }
    }

    "vscode" {
        if (Test-Path $VSCodeList) {
            Write-Host "📄 使用 VS Code 扩展清单：$VSCodeList"
            $Extensions = Get-ExtensionsFromTxt $VSCodeList
        } else {
            Write-Host "⚠️ 未找到 extensions-vscode.txt，直接使用 JSON"
            $Extensions = Get-ExtensionsFromJson
        }
    }

    "json" {
        Write-Host "📄 使用 extensions.json（不区分 Cursor / VS Code）"
        $Extensions = Get-ExtensionsFromJson
    }
}

# ------------------------------------------------------------
# Marketplace 查询
# ------------------------------------------------------------

function Get-LatestVsixInfo($ExtensionId) {

    $body = @{
        filters = @(
            @{
                criteria = @(
                    @{ filterType = 7; value = $ExtensionId }
                )
            }
        )
        flags = 914
    } | ConvertTo-Json -Depth 5

    $res = Invoke-RestMethod `
        -Method Post `
        -Uri $ApiUrl `
        -ContentType "application/json" `
        -Body $body

    if (!$res.results[0].extensions) {
        throw "未找到扩展：$ExtensionId"
    }

    $ext = $res.results[0].extensions[0]

    @{
        Publisher = $ext.publisher.publisherName
        Name      = $ext.extensionName
        Version   = $ext.versions[0].version
    }
}

function Remove-OldVsixVersions {
    param (
        [string]$Publisher,
        [string]$Name,
        [string]$KeepFileName
    )

    $pattern = "$Publisher.$Name-*.vsix"
    $candidates = Get-ChildItem -Path $OutDir -File -Filter $pattern -ErrorAction SilentlyContinue
    $removed = 0

    foreach ($item in $candidates) {
        if ($item.Name -ne $KeepFileName) {
            Remove-Item -Path $item.FullName -Force
            $removed++
            Write-Host "  清理旧版 $($item.Name)" -ForegroundColor DarkYellow
        }
    }

    return $removed
}

# ------------------------------------------------------------
# 下载
# ------------------------------------------------------------

Write-Host ""
Write-Host "⬇️  开始下载 [$Mode] 扩展" -ForegroundColor Cyan
Write-Host "📁 输出目录: $OutDir"
if ($PruneOldVersions) {
    Write-Host "🧹 清理策略: 保留每个扩展最新版本（删除旧版）" -ForegroundColor Cyan
}
Write-Host ""

$totalRemoved = 0

foreach ($id in $Extensions) {

    Write-Host "▶ $id" -ForegroundColor Cyan

    try {
        $info = Get-LatestVsixInfo $id
        $file = "$($info.Publisher).$($info.Name)-$($info.Version).vsix"
        $path = Join-Path $OutDir $file

        if (Test-Path $path) {
            Write-Host "  已存在，跳过" -ForegroundColor Yellow
        } else {
            $url = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$($info.Publisher)/vsextensions/$($info.Name)/$($info.Version)/vspackage"

            Invoke-WebRequest -Uri $url -OutFile $path
            Write-Host "  下载完成 $file" -ForegroundColor Green

            Start-Sleep -Seconds $SleepSeconds
        }

        if ($PruneOldVersions) {
            $totalRemoved += Remove-OldVsixVersions -Publisher $info.Publisher -Name $info.Name -KeepFileName $file
        }
    }
    catch {
        Write-Host "  下载失败 $id" -ForegroundColor Red
        Write-Host "  $_"
    }
}

Write-Host ""
Write-Host "✅ [$Mode] 扩展下载完成" -ForegroundColor Green
if ($PruneOldVersions) {
    Write-Host "🧹 共清理旧版文件: $totalRemoved" -ForegroundColor Green
}
