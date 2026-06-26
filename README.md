# common_records

本仓库用于收集可复用的 PowerShell 脚本，以及这些脚本的使用说明。

## 文档入口

- [Git 脚本](docs/git.md)：Git 历史改写、多仓库 checkout/pull 自动化。
- [文件同步脚本](docs/file-sync.md)：文件复制、同步与镜像工具。
- [Scoop 离线部署脚本](docs/scoop.md)：Scoop 离线 Bundle 构建、首次安装与后续更新流程。
- [VS Code / Cursor 脚本](docs/vscode-cursor.md)：扩展清单生成、VSIX 下载与批量安装。

## 脚本目录

- `scripts/git/`：Git 相关自动化脚本。
- `scripts/file-sync/`：文件同步脚本。
- `scripts/scoop/`：Scoop 离线部署脚本。
- `scripts/vscode-cursor/`：VS Code / Cursor 扩展管理脚本。

## Git 忽略规则

扩展清单、VSIX 离线包、日志和本地编辑器状态属于生成文件或本机环境文件，默认不纳入 Git。