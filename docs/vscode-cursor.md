# VS Code / Cursor 脚本

## 脚本索引

| 脚本 | 功能 | 详细说明 |
|---|---|---|
| [`scripts/vscode-cursor/Generate-Extensions.ps1`](../scripts/vscode-cursor/Generate-Extensions.ps1) | 从 `extensions.json` 生成 VS Code 和 Cursor 扩展 ID 清单。 | [Generate-Extensions.md](vscode-cursor/Generate-Extensions.md) |
| [`scripts/vscode-cursor/Download-Extensions.ps1`](../scripts/vscode-cursor/Download-Extensions.ps1) | 从 Visual Studio Marketplace 下载 VSIX 离线包。 | [Download-Extensions.md](vscode-cursor/Download-Extensions.md) |
| [`scripts/vscode-cursor/Install-VSCodeExtensions.ps1`](../scripts/vscode-cursor/Install-VSCodeExtensions.ps1) | 从扩展 ID 清单或本地 VSIX 文件批量安装扩展。 | [Install-VSCodeExtensions.md](vscode-cursor/Install-VSCodeExtensions.md) |
| [`scripts/vscode-cursor/restore-vscode-extensions.ps1`](../scripts/vscode-cursor/restore-vscode-extensions.ps1) | 从 VS Code 的 `state.vscdb` 恢复扩展 ID 并重新安装。 | [restore-vscode-extensions.md](vscode-cursor/restore-vscode-extensions.md) |

## 生成文件

`extensions-cursor.txt`、`extensions-vscode.txt` 和 `vsix/` 都是生成产物，默认不纳入 Git。