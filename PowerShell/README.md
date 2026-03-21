# 说明

## auto_rewrite_v1.ps1

批量自动处理仓库：修改指定仓库中(本地已克隆)所有 commits 中的 email，并推送到远端
**Notice:**

- 需要指定默认分支为master/main
- 如果还需要修改名字则需修改脚本内容：

```powershell
    # 新旧姓名
    $newName = "Your New Name"
    $oldName = "Old Name in Git History"

    # 新旧邮箱
    $newEmail = "921232958@qq.com"
    $oldEmail = "yangyukai@zwcad.com"

    # mailmap 里的格式：New Name <newEmail> Old Name <oldEmail>
    $mailmapText = "$newName <$newEmail> $oldName <$oldEmail>"
```

## auto_rewrite_v2.ps1

批量自动处理仓库：修改指定仓库中(本地未克隆)所有 commits 中的 email，并推送到远端(会克隆远端仓库到本地)
**Notice:**

- 需要指定每个仓库对应的分支
- 如果还需要修改名字则需修改脚本内容：

```powershell
    # 新旧姓名
    $newName = "Your New Name"
    $oldName = "Old Name in Git History"

    # 新旧邮箱
    $newEmail = "921232958@qq.com"
    $oldEmail = "yangyukai@zwcad.com"

    # mailmap 里的格式：New Name <newEmail> Old Name <oldEmail>
    $mailmapText = "$newName <$newEmail> $oldName <$oldEmail>"
```

## bimdevelop_checkoutpull.ps1

批量处理 `main` 目录下的 ZWBIM 相关仓库，按固定规则执行两阶段操作：

- 阶段一：`git checkout developbim`
- 阶段二：`git pull --progress -v --no-rebase origin developbim`

处理范围与原始 shell 脚本一致：

- 一级仓库目录直接执行（如 `IMModeling`、`AppFx`、`DBX` 等）
- 特殊分组目录做二级遍历（`AMEP`、`BIM`、`InternalCmds`、`Resources`、`SDKInc`）

### 参数

- `-MainDir`：主目录（默认：当前目录下的 `main`）
- `-Branch`：分支名（默认：`developbim`）
- `-Remote`：远程名（默认：`origin`）
- `-NoPause`：执行完不等待回车

### 示例

```powershell
# 默认执行（checkout + pull）
pwsh .\bimdevelop_checkoutpull.ps1

# 指定 main 目录
pwsh .\bimdevelop_checkoutpull.ps1 -MainDir "D:\work\main"

# 执行后不暂停
pwsh .\bimdevelop_checkoutpull.ps1 -NoPause
```

## bimdevelop_checkoutpull_enhanced.ps1

`bimdevelop_checkoutpull.ps1` 的增强版，增加了重试、日志、并行、演练模式和结果汇总，适合大规模仓库批处理。

### 增强能力

- 自动日志：写入 `.\logs\bimdevelop_checkoutpull_yyyyMMdd_HHmmss.log`
- 失败重试：每个仓库 checkout/pull 支持重试
- 结果汇总：统计成功/失败并列出失败仓库
- 可选并行：按 `ThrottleLimit` 分批并发执行
- 演练模式：`DryRun` 仅打印命令，不真正执行
- 模式切换：可只做 checkout 或只做 pull

### 参数

- `-MainDir`：主目录（默认：当前目录下的 `main`）
- `-Branch`：分支名（默认：`developbim`）
- `-Remote`：远程名（默认：`origin`）
- `-Mode`：`All | CheckoutOnly | PullOnly`（默认：`All`）
- `-RetryCount`：失败重试次数（默认：`2`）
- `-RetryDelaySeconds`：重试间隔秒数（默认：`2`）
- `-Parallel`：启用并行执行
- `-ThrottleLimit`：并行批次大小（默认：`6`）
- `-DryRun`：预演，不执行 git
- `-LogDir`：日志目录（默认：脚本目录下 `logs`）
- `-NoPause`：执行完不等待回车

### 示例

```powershell
# 全量执行（checkout + pull）
pwsh .\bimdevelop_checkoutpull_enhanced.ps1

# 只做 pull，失败重试 3 次
pwsh .\bimdevelop_checkoutpull_enhanced.ps1 -Mode PullOnly -RetryCount 3

# 并行执行，每批 8 个仓库
pwsh .\bimdevelop_checkoutpull_enhanced.ps1 -Parallel -ThrottleLimit 8

# 演练模式（不执行 git）
pwsh .\bimdevelop_checkoutpull_enhanced.ps1 -DryRun
```

### 建议

- 首次执行先用 `-DryRun` 确认目标仓库范围和命令
- 并行模式建议从 `-ThrottleLimit 4` 或 `6` 起步，观察网络和机器负载
- 失败仓库请按日志中的 `repo + step + exit code` 定位问题（权限、分支不存在、冲突等）
