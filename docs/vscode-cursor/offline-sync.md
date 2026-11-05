# VS Code 扩展离线同步

将外网 VS Code **当前已安装扩展及其准确版本、平台**同步到内网。先在外网更新扩展，再导出离线包；脚本不会自行追踪 Marketplace 最新版本。

## 快速使用

要求外网和内网均安装 PowerShell 7+，内网已安装 VS Code。

外网从仓库根目录执行：

```powershell
pwsh -File .\scripts\vscode-cursor\Export-VSCodeExtensions.ps1
```

默认生成 `scripts/vscode-cursor/offline-bundle/`。如需指定外网实例或搬运目录：

```powershell
pwsh -File .\scripts\vscode-cursor\Export-VSCodeExtensions.ps1 `
    -JsonPath 'D:\scoop\apps\vscode\current\data\extensions\extensions.json' `
    -OutputDir 'D:\transfer\vscode-extensions'
```

导出成功后，将**整个输出目录**复制到内网。在内网进入复制后的目录执行：

```powershell
pwsh -File .\Install-VSCodeExtensions.ps1
```

如果 `code` 不在 PATH：

```powershell
pwsh -File .\Install-VSCodeExtensions.ps1 `
    -CodeCmd 'D:\scoop\apps\vscode\current\bin\code.cmd'
```

## 脚本

| 脚本 | 功能 | 详细说明 |
|---|---|---|
| [Export-VSCodeExtensions.ps1](../../scripts/vscode-cursor/Export-VSCodeExtensions.ps1) | 导出固定版本 VSIX 和清单，成功后清理旧包。 | [导出说明](Export-VSCodeExtensions.md) |
| [Install-VSCodeExtensions.ps1](../../scripts/vscode-cursor/Install-VSCodeExtensions.ps1) | 内网镜像同步：安装目标、卸载多余扩展、核对集合与版本并清理旧包。 | [安装说明](Install-VSCodeExtensions.md) |
| [Remove-OfficialVSCodeUserData.ps1](../../scripts/vscode-cursor/Remove-OfficialVSCodeUserData.ps1) | 控制面板卸载官网版后，删除其默认本地用户数据，保护独立 Scoop 数据；默认预览。 | [用户数据清理说明](Remove-OfficialVSCodeUserData.md) |

`VSCodeExtensions.Common.ps1` 是两个入口的公共辅助文件，不需要单独运行。保留原有 `scripts/vscode-cursor/` 目录名，脚本功能仅面向 VS Code。

## 离线目录

```text
offline-bundle/
├── manifest.json
├── Install-VSCodeExtensions.ps1
├── VSCodeExtensions.Common.ps1
└── vsix/
    └── <id>-<version>-<platform>.vsix
```

重复同步时，先在外网更新扩展，再重跑导出并搬运整个目录。已有包通过校验后复用；新快照全部就绪后自动删除旧版本和已移除扩展的包。内网相同版本跳过，版本不同则覆盖安装，包括降级；目标核对成功后卸载清单外用户扩展，最终集合及版本与外网一致。

| 外网变化 | 离线目录 | 内网安装后的结果 |
|---|---|---|
| 扩展升级 | 下载新包，成功后删除旧包 | 升级到快照版本 |
| 扩展新增 | 下载并保留对应包 | 安装该扩展 |
| 扩展卸载 | 删除不再被清单引用的包 | 卸载该用户扩展 |
| 无变化 | 校验后复用 | 同版本跳过 |

内网搬运目录中因覆盖复制而遗留的旧 VSIX，也会在镜像同步成功后清理。历史版本不会自动归档；需要回滚时，应提前另存旧的完整离线目录。

## 同步范围

- 同步源是选定 `extensions.json` 中的已安装用户扩展，默认查找 Scoop 和常规用户目录。自定义 Profile 或实例通过 `-JsonPath` 选择，不自动合并。
- 导出未完成、缺包、包身份错误或 SHA-256 不符时，安装端会在安装任何扩展之前中止。
- 安装只引用清单中的本地 VSIX，禁止自动从 Marketplace 补充扩展包依赖；最终再次读取已安装版本核对。
- 建议内外网使用相同 VS Code 版本及操作系统、CPU 架构。版本或平台不兼容由 VS Code 报错，脚本会汇总失败。
- 同步包不包含 VS Code 安装程序、设置、快捷键、登录状态、启停状态，以及扩展运行时额外下载的语言服务器、SDK 或其他工具。这些资源需要另行离线准备。
- 内网额外的用户扩展会被卸载，包括内网自行安装而外网没有的扩展；同步范围是指定 VS Code 命令及 Profile 查询到的用户扩展，系统内置扩展不作为镜像删除目标。
- 下载失败不会清理旧包；内网目标安装或核对失败不会卸载额外扩展。合法空快照会清空对应用户扩展集合；非法或缺失数组会拒绝执行。

## 从旧流程迁移

`Generate-Extensions.ps1` 与 `Download-Extensions.ps1` 已由导出脚本替代。旧数据库恢复入口及 Cursor 分支已移除。安装脚本不再支持 `Mode`、`Source`、`ListPath` 和 `VsixDir`；旧 TXT 清单和散装 VSIX 不作为新流程输入，请在外网重新导出。

默认生成的离线目录和 VSIX 不纳入 Git。自定义输出目录建议放在仓库外。

## 验证

自动化测试使用模拟下载和隔离的假 VS Code CLI，不操作真实扩展：

```powershell
$config = New-PesterConfiguration
$config.Run.Path = '.\scripts\vscode-cursor\tests'
$config.TestRegistry.Enabled = $false
Invoke-Pester -Configuration $config
```

需要 Pester 5+；关闭 TestRegistry 后可在没有注册表写权限的环境运行。
