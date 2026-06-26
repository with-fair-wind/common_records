# Generate-Extensions.ps1

## 位置

`scripts/vscode-cursor/Generate-Extensions.ps1`

## 用途

读取 VS Code 的 `extensions.json`，生成 VS Code 和 Cursor 两套扩展 ID 清单。

## 参数

- `JsonPath`：可选，手动指定 `extensions.json` 路径。

## 路径解析顺序

未传入 `JsonPath` 时，脚本依次尝试：

1. `D:\scoop\apps\vscode\current\data\extensions\extensions.json`
2. `%USERPROFILE%\.vscode\extensions\extensions.json`

## 输出文件

- `extensions-vscode.txt`：完整扩展清单。
- `extensions-cursor.txt`：适合 Cursor 的过滤后清单。

## Cursor 过滤规则

Cursor 清单会排除不支持、无意义或编辑器内置相关的扩展，例如 Copilot、Remote、调试运行时、Azure/Kubernetes、Live Share 和 Jupyter 相关模式。

## 主要流程

1. 定位 `extensions.json`。
2. 读取每个扩展的 `identifier.id`。
3. 去重并排序。
4. 写入完整 VS Code 清单。
5. 写入过滤后的 Cursor 清单。