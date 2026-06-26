# auto_rewrite_v2.ps1

## 位置

`scripts/git/auto_rewrite_v2.ps1`

## 用途

批量改写多个 Git 仓库的提交邮箱。与 `auto_rewrite_v1.ps1` 相比，此版本会自动 clone 缺失的本地仓库，并为每个仓库配置主分支。

## 主要行为

- 使用脚本内硬编码的 `$oldEmail`、`$newEmail`、`$basePath`、`$githubUser` 和 `$repos`。
- `$repos` 中每项包含 `Name` 和 `Branch`。
- 本地目录不存在时执行 `git clone`。
- 执行 `git fetch origin` 并切换到配置的分支。
- 生成 `mailmap.txt`。
- 执行 `git filter-repo --mailmap mailmap.txt --force`。
- 如果 remote 缺失，则恢复 `origin`。
- 强推配置分支和 tags。
- 处理完成后删除 `mailmap.txt`。

## 依赖

- `git` 和 `git-filter-repo`。
- 有目标 GitHub 仓库的 SSH 访问权限。
- `$repos` 中的分支配置必须正确。

## 风险

该脚本同样会改写 Git 历史并强推。自动 clone 只降低准备成本，不降低历史改写风险。