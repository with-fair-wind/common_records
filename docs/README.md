# 文档导航

所有文档统一从本页进入；操作说明按分类存放，脚本及配套资源放在 `scripts/<分类>/`。

## Git

脚本目录：[scripts/git/](../scripts/git/)。

| 文档 | 用途 |
| --- | --- |
| [提交邮箱改写 v1](git/auto_rewrite_v1.md) | 改写已克隆仓库的提交邮箱并强推 |
| [提交邮箱改写 v2](git/auto_rewrite_v2.md) | 自动克隆缺失仓库，按仓库分支配置改写邮箱 |
| [递归 checkout / pull](git/git_recursive_checkout_pull.md) | 发现并批量更新多个 Git 仓库 |

## 文件同步

脚本目录：[scripts/file-sync/](../scripts/file-sync/)。

- [文件复制、同步与镜像](file-sync/copy_template.md)：多任务、多目标目录及白名单 / 黑名单配置。

## Scoop

脚本目录：[scripts/scoop/](../scripts/scoop/)。

- [离线 Bundle 使用指南](scoop/offline-bundle-usage.md)：外网构建、内网首次安装、后续更新、参数和排障。
- [Nerd Fonts 安装](scoop/nerd-fonts-install.md)：通过 Scoop 安装或升级字体。

## Neovim / LazyVim

脚本、Lua 配置、示例与测试：[scripts/nvim/](../scripts/nvim/)。

- [使用与配置教程](nvim/nvim-lazyvim-guide.md)：编辑操作、快捷键、Lua 配置、插件、Extras 与 clangd 来源。
- [Windows C++ 环境部署与脚本说明](nvim/nvim-cpp.md)：安装、启动、多机复用、构建验收、更新和恢复。

## VS Code

脚本目录：[scripts/vscode-cursor/](../scripts/vscode-cursor/)，保留原目录名，功能面向 VS Code。

- [扩展离线同步流程](vscode-cursor/offline-sync.md)：外网导出、内网同步、适用范围和验证。
- [导出扩展](vscode-cursor/Export-VSCodeExtensions.md)：固定版本 VSIX、清单和导出参数。
- [安装扩展](vscode-cursor/Install-VSCodeExtensions.md)：离线镜像安装、版本核对与多余扩展清理。
- [官网版用户数据清理](vscode-cursor/Remove-OfficialVSCodeUserData.md)：卸载官网版后的本地数据清理与 Scoop 数据保护。

## omp

- [日常速查](omp/quick-reference.md)：oh-my-pi 常用配置、命令、快捷键及 Windows 按键冲突处理。
