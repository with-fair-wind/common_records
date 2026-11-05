# Install-VSCodeExtensions.ps1

在内网按 `manifest.json` 镜像同步 VS Code 用户扩展，包含卸载清单外的扩展。要求 PowerShell 7+ 和本机 VS Code。

## 使用

推荐运行导出目录内自带的安装脚本，默认读取同目录下的清单：

```powershell
pwsh -File .\Install-VSCodeExtensions.ps1
```

也可以使用仓库中的脚本，显式指定离线目录：

```powershell
pwsh -File .\scripts\vscode-cursor\Install-VSCodeExtensions.ps1 `
    -BundleDir 'E:\vscode-extensions' `
    -CodeCmd 'D:\scoop\apps\vscode\current\bin\code.cmd'
```

## 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `BundleDir` | 安装脚本所在目录 | 包含 `manifest.json` 和 `vsix/` 的离线目录。 |
| `CodeCmd` | `code` | VS Code CLI 命令或 `code.cmd` 的完整路径。 |
| `ProfileName` | VS Code 默认 Profile | 可选，选择内网目标 Profile；所有查询、安装和卸载均传入此参数。 |

`CodeCmd` 只传命令或文件路径，不在字符串中拼接命令参数。使用 `-Verbose` 可查看成功安装时的 CLI 输出；失败输出会写入警告。

## 执行流程

1. 验证清单版本、完成标记及扩展数组，拒绝重复 ID 和无效文件名。
2. 对全部条目检查 VSIX 是否存在、SHA-256 是否一致，以及包内 ID、版本、平台是否与清单一致。任何包失败都在调用 VS Code 前中止。
3. 用 `code --list-extensions --show-versions` 查询已安装版本。
4. 相同版本跳过；其他版本执行本地 VSIX 安装，附带 `--force`，允许恢复到外网指定的版本。
5. 附带 `--do-not-include-pack-dependencies`，使清单内的本地包负责提供依赖，避免自动从 Marketplace 补装扩展包内容。该参数由 VS Code CLI 源码支持，属于未在 CLI 帮助中公开的选项；若目标版本不支持，应先升级或统一内外网 VS Code 版本。
6. 单个扩展安装失败后继续其他扩展，保留错误输出；再次查询全部已安装版本，检查清单中的每个 ID 是否匹配。任何目标安装失败或版本不符，都停止在此阶段，不卸载额外扩展。
7. 目标全部就绪后，卸载内网已安装但不在清单中的用户扩展。如果依赖关系阻止卸载，其他扩展移除后有实际进展才重试；没有进展则报告失败。
8. VS Code 卸载扩展包可能连带移除包内扩展，脚本会从本地 VSIX 恢复仍在目标清单中的成员，再核对最终集合及版本。
9. 用户扩展镜像同步成功后，清理内网离线目录 `vsix/` 中清单未引用的直属 `.vsix`，以及脚本格式的中断下载临时文件。这样即使搬运时只覆盖复制，目标目录也不会继续累积旧包。
10. 输出安装、跳过、卸载及失败数量；安装、卸载、最终核对或旧包清理任一失败都抛错，供 `pwsh -File` 返回非零退出码。

最终的用户扩展 ID 集合和版本与外网快照一致。目录中的额外旧包不会安装，内网自行安装而外网没有的用户扩展也会卸载。系统内置扩展不在用户扩展镜像清单中。重跑时已匹配版本自动跳过。

合法空快照（`complete=true` 且 `extensions=[]`）表示目标不保留任何用户扩展，会卸载查询到的全部用户扩展并清理直属 VSIX。`extensions=null`、缺少字段及未完成快照会被拒绝。

请重新运行新版导出脚本，并将整个输出目录复制到内网，以使用随包附带的新版安装脚本和公共辅助文件。旧包中自带的旧安装脚本仍遵循当时的行为。

## 限制

镜像同步以用户扩展 ID 和版本为准，不同步启停状态、用户配置或账户登录；卸载时的数据处理遵循 VS Code 的行为。平台兼容性由 VS Code 安装器检查。SHA-256 用于检测文件变化，不替代发布者签名验证。

脚本通过指定的 `CodeCmd` 和 `ProfileName` 操作目标实例。VS Code 的应用级扩展可能跨 Profile 共享，卸载行为仍遵循 VS Code 本身的规则。

扩展首次运行可能还需要语言服务器、SDK 或外部程序，需单独准备；同步 VSIX 并不保证这些运行时资源已可离线使用。

CLI 参数依据：[VS Code CLI 文档](https://code.visualstudio.com/docs/configure/command-line)、[VS Code CLI 安装实现](https://github.com/microsoft/vscode/blob/main/src/vs/code/node/cliProcessMain.ts)。
