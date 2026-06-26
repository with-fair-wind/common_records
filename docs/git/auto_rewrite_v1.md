# auto_rewrite_v1.ps1

## 位置

`scripts/git/auto_rewrite_v1.ps1`

## 用途

批量改写已经克隆到本地的 Git 仓库提交邮箱，并把改写后的分支和标签推送到 GitHub。

## 主要行为

- 使用脚本内硬编码的 `$oldEmail`、`$newEmail`、`$repos`、`$basePath` 和 `$githubUser`。
- 对每个仓库解析 `<basePath>\<repo>` 目录。
- 生成临时 `mailmap.txt`。
- 执行 `git filter-repo --mailmap mailmap.txt --force`。
- 如果仓库没有 remote，则恢复 `origin`。
- 使用 `--force-with-lease` 推送 `main` 和 tags；遇到 stale info 时退回 `--force`。
- 处理完成后删除 `mailmap.txt`。

## 依赖

- `git` 可用。
- 已安装 `git-filter-repo`，并可通过 `git filter-repo` 调用。
- 有目标 GitHub 仓库的 SSH 推送权限。
- 本地仓库目录已经存在。

## 风险

该脚本会改写提交 ID 并强推远端历史。执行前需要确认备份、协作方状态和远端分支归属。