# Build-ScoopOfflineBundle.ps1

## 位置

`scripts/scoop/Build-ScoopOfflineBundle.ps1`

## 用途

在外网机器上构建可复制的 Scoop 离线 Bundle。该 Bundle 可同步到内网机器，用于首次安装或后续更新 Scoop 环境。

## 参数

- `ScoopRoot`：外网机器 Scoop 根目录，默认是 `D:\scoop`。
- `BundleRoot`：输出 Bundle 目录，默认是 `D:\ScoopOfflineBundle`。
- `CacheRoot`：可选的 Scoop cache 目录覆盖值。

## 主要流程

1. 校验 Scoop 根目录、cache 目录和输出路径。
2. 定义 `$RequestedPackages`，当前包括 `7zip`、`clangd`、`cmake`、`ninja`、`llvm`、`extras/vscode`、`extras/windows-terminal`、`versions/windows-terminal-preview`。
3. 通过 `scoop depends` 解析依赖闭包。
4. 使用 `scoop download --no-update-scoop` 下载所需包到 Scoop cache。
5. 按当前 manifest 版本筛选需要打入 Bundle 的 cache 文件。
6. 将 Scoop 核心打包为 `scoop-core.zip`。
7. 将涉及到的 bucket 打包为 `buckets.zip`。
8. 以硬链接或复制的方式把 cache 文件放入 Bundle。
9. 写入 `bundle.json`，包含格式版本、架构、包元数据、bucket 列表、cache 哈希和 zip 哈希。
10. 构建成功后原子替换旧 Bundle。

## 输出目录

默认输出：

```text
D:\ScoopOfflineBundle
```

## 使用建议

正式构建前建议先在外网机器执行 `scoop update`，确保本地 manifest 已更新。