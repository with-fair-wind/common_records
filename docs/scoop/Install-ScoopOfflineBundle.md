# Install-ScoopOfflineBundle.ps1

## 位置

`scripts/scoop/Install-ScoopOfflineBundle.ps1`

## 用途

在内网机器上通过离线 Bundle 首次部署 Scoop。

## 参数

- `BundleRoot`：同步后的 Bundle 目录，默认是 `D:\ScoopOfflineBundle`。
- `ScoopRoot`：目标 Scoop 根目录，默认是 `D:\scoop`。
- `CacheRoot`：可选 cache 目录，默认是 `<ScoopRoot>\cache`。
- `Force`：当 `ScoopRoot` 非空时删除该目录后重新部署，仅适合首次安装失败后的重试。

## 主要流程

1. 校验 Bundle 必要文件。
2. 读取 `bundle.json`。
3. 接受 `FormatVersion` 1 和 2。
4. 校验架构、`scoop-core.zip` 哈希和 `buckets.zip` 哈希。
5. 除非传入 `-Force`，否则拒绝安装到非空 `ScoopRoot`。
6. 解压 Scoop 核心和 bucket。
7. 若存在 `BundledBuckets` 元数据，则按该字段校验 bucket 目录。
8. 对旧格式 Bundle，回退校验 `main` 和 `extras`。
9. 按长度和 SHA-256 复制并校验 cache 文件。
10. 设置用户级 `SCOOP`、`SCOOP_CACHE` 和 `Path`。
11. 创建引导用 `scoop.cmd` 和 `scoop.ps1` shim。
12. 设置 Scoop 的 `last_update`。
13. 若请求列表包含 `7zip`，先安装 `7zip`，再安装其他请求包，并使用 `--no-update-scoop`。

## 使用边界

该脚本只用于首次部署或确认要完整重装时。正常后续更新应使用 `Update-ScoopOfflineBundle.ps1`。

## 最近修正

脚本已同步兼容当前 Build 输出：同时支持 Bundle 格式版本 1 和 2，并使用动态 `BundledBuckets` 校验 bucket，而不是只写死 `main` 和 `extras`。