# =========================================================
# Generate-CursorExtensions.ps1
# 自动从 %USERPROFILE%\.vscode\extensions\extensions.json
# 生成 Cursor / VS Code 扩展清单
# =========================================================

$ErrorActionPreference = "Stop"

# 自动定位用户目录下的 extensions.json
$UserProfile = $env:USERPROFILE
$Input = Join-Path $UserProfile ".vscode\extensions\extensions.json"

$OutCursor = "extensions-cursor.txt"
$OutVSCode = "extensions-vscode.txt"

if (!(Test-Path $Input)) {
    Write-Error "找不到 extensions.json：$Input"
    Write-Error "请确认文件存在于 .vscode\extensions 目录下"
    exit 1
}

# Cursor 明确不支持 / 无意义的扩展前缀
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

Write-Host "📄 使用扩展清单：" -NoNewline
Write-Host $Input -ForegroundColor Cyan

$data = Get-Content $Input -Raw | ConvertFrom-Json

# VS Code 导出的 JSON 通常是数组，每项有 identifier.id
$all = $data | ForEach-Object {
    $_.identifier.id
} | Sort-Object -Unique

$cursor = @()
$vscode = @()

foreach ($id in $all) {

    $excluded = $false
    foreach ($pattern in $ExcludePatterns) {
        if ($id -match $pattern) {
            $excluded = $true
            break
        }
    }

    if ($excluded) {
        $vscode += $id
    } else {
        $cursor += $id
        $vscode += $id
    }
}

$cursor | Sort-Object | Set-Content $OutCursor -Encoding UTF8
$vscode | Sort-Object | Set-Content $OutVSCode -Encoding UTF8

Write-Host ""
Write-Host "✅ 已生成扩展清单：" -ForegroundColor Green
Write-Host "  Cursor  : $OutCursor ($($cursor.Count))"
Write-Host "  VS Code : $OutVSCode ($($vscode.Count))"
