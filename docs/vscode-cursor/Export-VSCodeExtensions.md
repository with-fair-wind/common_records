# Export-VSCodeExtensions.ps1

读取外网 VS Code 的已安装扩展记录，导出固定版本的 VSIX 和离线同步清单。要求 PowerShell 7+，外网能访问 Visual Studio Marketplace 及其下载重定向地址。

## 使用

先在外网 VS Code 完成扩展更新，再执行：

```powershell
pwsh -File .\scripts\vscode-cursor\Export-VSCodeExtensions.ps1
```

默认输出到脚本目录下的 `offline-bundle/`，与执行命令时的工作目录无关。

```powershell
pwsh -File .\scripts\vscode-cursor\Export-VSCodeExtensions.ps1 `
    -JsonPath 'D:\scoop\apps\vscode\current\data\extensions\extensions.json' `
    -OutputDir 'D:\transfer\vscode-extensions'
```

## 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `JsonPath` | 自动查找 | 外网 VS Code 的已安装扩展 JSON，手动指定时优先使用。 |
| `OutputDir` | 脚本目录下 `offline-bundle` | 输出目录；显式传入相对路径时相对当前工作目录。 |
| `RetryCount` | `2` | 每个扩展首次下载失败后的重试次数。 |
| `RetryDelaySeconds` | `2` | 重试间隔，单位为秒。 |

自动查找顺序：

1. 设置了 `VSCODE_EXTENSIONS` 时，使用该目录下的 `extensions.json`。
2. `D:\scoop\apps\vscode\current\data\extensions\extensions.json`。
3. `%USERPROFILE%\.vscode\extensions\extensions.json`。

多个 VS Code 实例、其他便携目录或自定义 Profile，应显式指定对应的已安装扩展 JSON。不会合并多个实例或 Profile。工作区 `.vscode/extensions.json` 是推荐清单，不能作为输入。

## 导出行为

- 从记录中读取 `identifier.id`、`version` 和 `metadata.targetPlatform`。缺省平台或 `undefined` 按通用包处理。
- 下载所记录的准确版本及平台，不查询 Marketplace 最新版本，不自动更新本机扩展。
- 相同记录去重；同一 ID 出现不同版本或平台时拒绝导出，避免任意选择。
- 下载到临时文件，校验 ZIP、包内 `package.json` 和 VSIX Identity 的 ID、版本、平台后，才替换正式文件。
- 生成 SHA-256；再次导出时，已有包必须同时通过包信息校验和旧清单哈希校验才可复用。
- 每处理一个扩展保存一次清单。只要有失败，`complete` 就保持 `false`，记录失败原因，并以错误结束。重跑可继续复用已成功的包。
- 清单使用临时文件替换写入；开始下载前先将新清单标记为未完成，避免中断后误用旧的完成标记。
- 将安装脚本及公共辅助文件复制进输出目录，整个目录即可搬运到内网。
- 所有目标包均就绪后，自动删除 `vsix/` 中未被新清单引用的直属 `.vsix` 文件，包括旧版本、旧平台和外网已卸载扩展的包；也清理符合脚本命名规则的中断下载临时文件。
- 不递归清理其他子目录，不删除笔记等无关文件；拒绝通过目录联接或符号链接重定向的 VSIX 路径。
- 下载失败时不清理旧包；清理失败时保留 `complete=false` 并抛错。下载及清理均成功后才标记整个导出完成。

离线目录是当前外网扩展快照，不作为历史包仓库。若需保留回滚版本，应将旧的完整离线目录另行归档，导出成功后其中的旧包会被自动清理。

显式的空数组 `[]` 表示外网没有任何用户扩展，是有效快照：导出会清空直属 VSIX 包，内网镜像同步会卸载所选目标中的全部用户扩展。缺少 `extensions` 数组、工作区推荐 JSON、非法记录均不会当作空快照处理。

未上架、已下架或无权下载的私有扩展会使导出未完成。脚本不会将本机解压目录重新打包，或静默替换成其他版本。修复来源后重新导出，或从外网待同步扩展集合中移除不需要的扩展后再导出。

## 清单

`manifest.json` 包含 `schemaVersion`、UTC 导出时间、`complete` 以及 `extensions` 数组。每项记录：

| 字段 | 含义 |
|---|---|
| `id` | 扩展 ID |
| `version` | 外网实际安装版本 |
| `targetPlatform` | `universal` 或安装记录中的平台，例如 `win32-x64` |
| `file` | `vsix/` 中的文件名，包含 ID、版本和平台 |
| `sha256` | 下载包的 SHA-256 |
| `status` | `pending`、`ready` 或 `failed` |
| `error` | 失败原因；成功时为 `null` |

不要手工把 `complete` 改为 `true` 绕过缺包检查。
