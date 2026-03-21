# VSCode extension recovery script
# 从 state.vscdb 恢复扩展列表并重新安装

# 自动查找 VSCode 用户目录
$possiblePaths = @(
"D:\scoop\persist\vscode\data\user-data\User\globalStorage\state.vscdb"
)

$dbPath = $null

foreach ($p in $possiblePaths) {
    if (Test-Path $p) {
        $dbPath = $p
        break
    }
}

if (-not $dbPath) {
    Write-Host "❌ 未找到 state.vscdb"
    exit
}

Write-Host "✔ 找到数据库: $dbPath"

# 需要 sqlite3
$sqlite = "sqlite3"

try {
    $json = & $sqlite $dbPath "SELECT value FROM ItemTable WHERE key='extensionsIdentifiers/installed';"
} catch {
    Write-Host "❌ 未找到 sqlite3，请先安装 sqlite"
    exit
}

if (-not $json) {
    Write-Host "❌ 未找到扩展数据"
    exit
}

# 解析 JSON
$extensions = $json | ConvertFrom-Json

Write-Host ""
Write-Host "发现扩展数量:" $extensions.Count
Write-Host ""

foreach ($ext in $extensions) {

    $id = $ext.id
    Write-Host "安装扩展:" $id

    code --install-extension $id
}

Write-Host ""
Write-Host "✔ 扩展恢复完成"