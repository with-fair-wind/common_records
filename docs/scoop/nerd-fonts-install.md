# nerd-fonts-install.ps1

## 位置

`scripts/scoop/nerd-fonts-install.ps1`

## 用途

通过 Scoop 安装一组常用 Nerd Fonts，也可以列出默认字体清单或升级已安装字体。

## 参数

- `Fonts`：可选字体 manifest 名称列表。
- `Upgrade`：对已安装字体执行升级，而不是跳过。
- `UpdateScoop`：字体操作前执行 `scoop update`。
- `NoBucketAdd`：不自动添加 `nerd-fonts` bucket。
- `List`：输出默认字体清单后退出。
- `WhatIf`：通过 `SupportsShouldProcess` 支持演练模式。

## 默认字体

- `cascadiacode-nf-mono`
- `jetbrainsmono-nf-mono`
- `firacode-nf-mono`
- `hack-nf-mono`
- `iosevka-nf-mono`
- `dejavusansmono-nf-mono`
- `sourcecodepro-nf-mono`
- `ubuntu-nf-mono`

## 主要流程

1. 检查 `scoop` 是否可用。
2. 可选更新 Scoop 和 buckets。
3. 除非使用 `NoBucketAdd`，否则确保存在 `nerd-fonts` bucket。
4. 读取已安装 Scoop 应用。
5. 安装缺失字体。
6. 根据 `Upgrade` 决定跳过或升级已安装字体。
7. 输出成功、跳过和失败统计。