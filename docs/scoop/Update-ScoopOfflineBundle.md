# Update-ScoopOfflineBundle.ps1

## 位置

`scripts/scoop/Update-ScoopOfflineBundle.ps1`

## 用途

使用同步后的离线 Bundle 更新已有内网 Scoop 安装。

## 参数

- `BundleRoot`：同步后的 Bundle 目录，默认是 `D:\ScoopOfflineBundle`。
- `ScoopRoot`：已有 Scoop 根目录，默认是 `D:\scoop`。
- `CacheRoot`：可选 cache 目录，默认从 `SCOOP_CACHE`、Scoop 配置或 `<ScoopRoot>\cache` 推断。
- `SkipAppUpdate`：只更新核心、bucket 和 cache，不更新应用。
- `StopRunningProcesses`：强制关闭可能占用文件的相关进程。
- `KeepBackupCount`：保留的核心/bucket 备份数量。

## 主要流程

1. 校验 Bundle 文件、哈希、架构和 cache 元数据。
2. 要求已有 `apps\scoop\current` 核心目录。
3. 解析本地 cache 路径。
4. 将新的核心和 bucket 解压到暂存目录。
5. 从 `buckets.zip` 动态识别包含的 bucket。
6. 检测 `Code`、`clangd`、`clang`、`cmake`、`ninja`、Windows Terminal 等可能占用文件的进程。
7. 将 Bundle cache 文件复制或硬链接到本地 Scoop cache。
8. 将旧核心和旧 bucket 移动到 `offline-backups`。
9. 将新核心和新 bucket 移动到正式位置。
10. 若替换失败，尝试回滚已移动目录。
11. 刷新 Scoop 环境变量和引导 shim。
12. 除非传入 `SkipAppUpdate`，否则更新 Bundle 中已在内网安装的软件。
13. 清理暂存目录和过旧备份。

## 适用场景

外网构建新 Bundle 并同步到内网后，使用该脚本更新已有内网 Scoop 环境。