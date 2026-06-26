# Git 脚本

## 脚本索引

| 脚本 | 功能 | 详细说明 |
|---|---|---|
| [`scripts/git/auto_rewrite_v1.ps1`](../scripts/git/auto_rewrite_v1.ps1) | 对已克隆到本地的仓库改写提交邮箱，并强推改写后的分支和标签。 | [auto_rewrite_v1.md](git/auto_rewrite_v1.md) |
| [`scripts/git/auto_rewrite_v2.ps1`](../scripts/git/auto_rewrite_v2.ps1) | 自动克隆缺失仓库，再按每个仓库配置的分支改写提交邮箱。 | [auto_rewrite_v2.md](git/auto_rewrite_v2.md) |
| [`scripts/git/git_recursive_checkout_pull.ps1`](../scripts/git/git_recursive_checkout_pull.ps1) | 递归发现 Git 仓库并批量 checkout/pull。 | [git_recursive_checkout_pull.md](git/git_recursive_checkout_pull.md) |

## 安全提示

`auto_rewrite_*` 脚本会改写 Git 历史并强推结果。使用前需要确认仓库归属、远端状态和备份情况。