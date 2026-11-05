# Remove-OfficialVSCodeUserData.ps1

用于“卸载官网版 VS Code，只保留独立的 Scoop 便携版”场景。先通过控制面板或 Windows 的“已安装的应用”卸载官网版，再用脚本删除当前 Windows 用户的默认本地数据。

要求 Windows 和 PowerShell 7+。默认只预览；指定 `-Apply` 才执行。删除包括设置、扩展及备份，无法由脚本恢复。

## 删除范围

| 目录 | 删除的内容 |
|---|---|
| `%APPDATA%\Code` | 设置、快捷键、Profile、工作区状态、扩展状态、本地历史、备份、日志、会话和缓存 |
| `%USERPROFILE%\.vscode` | 默认位置的已安装扩展及本机配置 |
| `%USERPROFILE%\.vscode-shared` | 默认位置的共享数据 |

删除整个目录，所以这属于用户数据清理，不是只清缓存。上述三个目录对应 VS Code 官方文档中的 clean uninstall 范围。

官网的 User Installer 和 System Installer 在同一 Windows 用户下通常共用这些数据目录，因此不再区分 `Scope`。脚本只处理当前用户，不扫描其他用户目录或磁盘上的任意 `.vscode` 文件夹，也不会删除项目内的 `.vscode`。

## 使用

先卸载官网安装版，然后在仓库根目录预览：

```powershell
pwsh -File .\scripts\vscode-cursor\Remove-OfficialVSCodeUserData.ps1
```

检查输出路径，确认其中的数据不再需要后执行：

```powershell
pwsh -File .\scripts\vscode-cursor\Remove-OfficialVSCodeUserData.ps1 -Apply
```

只有 `Apply` 一个业务参数。`-WhatIf` 可使 `-Apply` 仍只预览；`-Confirm` 可逐项确认。已不存在的目录跳过，重复执行没有目录可删时直接结束。

## 执行流程

1. 根据当前用户的 `APPDATA` 和 `USERPROFILE` 生成三个固定候选路径，只列出实际存在的目录。
2. 全量检查目标必须为允许范围内的绝对路径，不能位于 Scoop 下，目标及祖先不能是符号链接或目录联接。
3. 输出待删除目录及数据范围；不带 `-Apply` 时结束。
4. 检查官网用户版和系统版的标准安装位置是否仍有 `Code.exe`。如果仍存在，要求先在控制面板卸载，不执行删除。
5. 检查已识别的 Scoop VS Code 是否使用独立的便携 `data`；非便携模式可能共用默认用户数据，因此拒绝清理。若 `VSCODE_EXTENSIONS` 指向待删除目录且存在 Scoop 安装，也拒绝执行。
6. 检查 Code 进程。可确认独立存储的便携 Scoop 可以继续运行；其他可能使用默认数据的进程需先关闭。脚本不结束进程。
7. 逐项经过 `ShouldProcess`，再次验证路径及 Scoop 数据隔离，使用 `Remove-Item -LiteralPath ... -Recurse -Force` 删除整个目录并汇总数量。

目录删除遇到权限或文件占用错误时停止，不会忽略错误后宣称全部成功。

## 与 Scoop 的关系

Scoop 便携版的设置、扩展和共享数据通常分别存放在 `data\user-data`、`data\extensions`、`data\shared-data`。它们及 Scoop 的 `apps`、`persist`、`shims` 不在清理范围内。

不过默认目录不会记录“由哪种安装方式产生”，也可能被其他非便携实例共用。脚本通过环境变量、标准 Scoop 根目录和 `code` 命令路径识别 Scoop，并拒绝已知共享情况；自定义的启动参数或未被识别的其他实例，需要使用者确认没有共用这些路径。

## 不处理的内容

- 应用卸载、安装目录、PATH、注册表关联和快捷方式：由控制面板中的卸载程序处理。
- 自定义 `--user-data-dir`、`--extensions-dir`、共享目录以及 Insiders 的数据：不扫描，不推断归属。
- 云端设置同步、外部账号、项目代码、项目配置和独立 SDK：不修改。
- `%LOCALAPPDATA%\Code` 等未列出的目录：不按名称猜测并删除。

这里的“彻底删除”指官方文档列出的默认本地用户数据，不代表扫描所有自定义目录或清除所有系统痕迹。

此前的缓存专用入口已由此脚本替代；本脚本不会调用官网卸载程序。

## 测试

```powershell
$config = New-PesterConfiguration
$config.Run.Path = '.\scripts\vscode-cursor\tests\Remove-OfficialVSCodeUserData.Tests.ps1'
$config.TestRegistry.Enabled = $false
Invoke-Pester -Configuration $config
```

测试只操作临时目录中的模拟数据，验证预览、完整删除、未卸载时阻止、Scoop 保护、重定向拒绝及项目数据保留。未删除真实用户数据。

参考：[VS Code 官方 clean uninstall 说明](https://code.visualstudio.com/docs/setup/uninstall)、[便携模式](https://code.visualstudio.com/docs/setup/portable)、[VS Code 数据目录实现](https://github.com/microsoft/vscode/blob/main/src/vs/platform/environment/common/environmentService.ts)。
