# Scoop 离线部署脚本

## 脚本索引

| 脚本 | 功能 | 详细说明 |
|---|---|---|
| [`scripts/scoop/Build-ScoopOfflineBundle.ps1`](../scripts/scoop/Build-ScoopOfflineBundle.ps1) | 在外网机器构建可复制到内网的 Scoop 离线 Bundle。 | [Build-ScoopOfflineBundle.md](scoop/Build-ScoopOfflineBundle.md) |
| [`scripts/scoop/Install-ScoopOfflineBundle.ps1`](../scripts/scoop/Install-ScoopOfflineBundle.ps1) | 在内网机器上通过离线 Bundle 首次安装 Scoop。 | [Install-ScoopOfflineBundle.md](scoop/Install-ScoopOfflineBundle.md) |
| [`scripts/scoop/Update-ScoopOfflineBundle.ps1`](../scripts/scoop/Update-ScoopOfflineBundle.ps1) | 使用同步后的 Bundle 更新已有内网 Scoop 环境。 | [Update-ScoopOfflineBundle.md](scoop/Update-ScoopOfflineBundle.md) |
| [`scripts/scoop/nerd-fonts-install.ps1`](../scripts/scoop/nerd-fonts-install.ps1) | 通过 Scoop 安装或升级常用 Nerd Fonts。 | [nerd-fonts-install.md](scoop/nerd-fonts-install.md) |

## 详细指南

- [Scoop 离线 Bundle 使用指南](scoop/offline-bundle-usage.md)

## 格式兼容性

`Build-ScoopOfflineBundle.ps1` 当前生成 Bundle 格式版本 2。`Install-ScoopOfflineBundle.ps1` 同时兼容格式版本 1 和 2，并会在存在 `BundledBuckets` 元数据时按该字段校验 bucket。