# restore-vscode-extensions.ps1

## 位置

`scripts/vscode-cursor/restore-vscode-extensions.ps1`

## 用途

旧版恢复脚本。它从 VS Code 的 `state.vscdb` 中读取已安装扩展 ID，并通过 `code --install-extension` 重新安装。

## 主要流程

1. 查找配置好的 VS Code `state.vscdb` 路径。
2. 使用 `sqlite3` 查询 `ItemTable` 中的 `extensionsIdentifiers/installed`。
3. 解析返回的 JSON。
4. 对每个扩展 ID 执行 `code --install-extension`。

## 依赖

- `sqlite3` 在 `PATH` 中可用。
- `code` 在 `PATH` 中可用。
- 配置的 `state.vscdb` 路径存在。

## 说明

该脚本比新的 VS Code/Cursor 扩展工作流更窄。需要可重复的在线或离线扩展管理时，优先使用 `Generate-Extensions.ps1`、`Download-Extensions.ps1` 和 `Install-VSCodeExtensions.ps1`。