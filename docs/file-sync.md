# 文件同步脚本

## 脚本索引

| 脚本 | 功能 | 详细说明 |
|---|---|---|
| [`scripts/file-sync/copy_template.ps1`](../scripts/file-sync/copy_template.ps1) | 可配置的多任务复制、同步、镜像脚本，支持白名单和黑名单。 | [copy_template.md](file-sync/copy_template.md) |

## 安全提示

`Mirror` 模式会删除目标目录中不属于源端选择范围的文件。若需要保留目标目录中的额外文件，请使用 `Sync` 模式。