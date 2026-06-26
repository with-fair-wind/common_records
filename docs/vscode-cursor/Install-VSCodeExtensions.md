# Install-VSCodeExtensions.ps1

## 位置

`scripts/vscode-cursor/Install-VSCodeExtensions.ps1`

## 用途

批量安装 VS Code 或 Cursor 扩展。安装来源可以是扩展 ID 清单，也可以是本地 `.vsix` 文件。

## 参数

- `Mode`：`vscode` 或 `cursor`，默认是 `vscode`。
- `Source`：`list` 或 `vsix`，默认是 `list`。
- `ListPath`：可选，手动指定扩展 ID 清单路径。
- `VsixDir`：可选，手动指定本地 VSIX 目录。
- `CodeCmd`：可选，手动指定编辑器命令。默认 VS Code 使用 `code`，Cursor 使用 `cursor`。

## 安装来源

- `list`：读取 `extensions-vscode.txt` 或 `extensions-cursor.txt`，执行 `<CodeCmd> --install-extension <id>`。
- `vsix`：扫描本地 VSIX 目录，执行 `<CodeCmd> --install-extension <file>`。

## 主要流程

1. 解析编辑器命令。
2. 解析输入清单或 VSIX 目录。
3. 逐个安装扩展。
4. 记录失败项。
5. 输出最终成功或失败汇总。

## 依赖

除非通过 `CodeCmd` 指定可执行文件，否则 `code` 或 `cursor` 需要在 `PATH` 中可用。