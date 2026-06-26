# Download-Extensions.ps1

## 位置

`scripts/vscode-cursor/Download-Extensions.ps1`

## 用途

按 VS Code 或 Cursor 扩展清单下载最新 `.vsix` 包，适合准备离线或内网安装资源。

## 参数

- `Mode`：`cursor`、`vscode` 或 `json`，默认是 `cursor`。
- `JsonPath`：可选，手动指定 `extensions.json` 路径。
- `PruneOldVersions`：下载最新版本后删除同扩展旧版本 VSIX 文件。

## 输入来源

- `cursor`：优先使用 `extensions-cursor.txt`；不存在时从 `extensions.json` 动态过滤。
- `vscode`：优先使用 `extensions-vscode.txt`；不存在时使用 `extensions.json` 中全部 ID。
- `json`：直接使用 `extensions.json` 中全部 ID。

## 输出目录

- `scripts\vscode-cursor\vsix\cursor`
- `scripts\vscode-cursor\vsix\vscode`
- `scripts\vscode-cursor\vsix\json`

## 主要流程

1. 解析扩展来源清单。
2. 查询 Visual Studio Marketplace 扩展 API。
3. 读取发布者、扩展名和最新版本号。
4. 目标 VSIX 不存在时下载。
5. 可选清理旧版本。
6. 单个扩展失败时继续处理后续扩展。

## 依赖

需要能访问 `marketplace.visualstudio.com`。