# git_recursive_checkout_pull.ps1 使用文档

## 概述

递归扫描指定目录下的所有 Git 仓库，批量执行 `checkout` 切换分支和 `pull` 拉取更新。

适用于管理大量子仓库的工作流（如多模块 C++ 项目、微服务集群、monorepo 等）。脚本不依赖硬编码仓库列表，通过自动发现 `.git` 目录来识别仓库，适配任意目录结构。

---

## 环境要求

| 依赖 | 要求 |
|------|------|
| PowerShell | 5.1+ 或 PowerShell 7+ |
| Git | 已安装且在 PATH 中 |
| ThreadJob 模块 | 并行模式需要（`Install-Module ThreadJob`），不可用时自动回退顺序执行 |

---

## 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `-MainDir` | string | 当前目录下的 `main` | 主目录路径，从此目录开始递归扫描 Git 仓库 |
| `-Branch` | string | `developbim` | 要 checkout/pull 的目标分支名 |
| `-Remote` | string | `origin` | 远程仓库名称 |
| `-Mode` | enum | `All` | 执行模式：`All` / `CheckoutOnly` / `PullOnly` |
| `-RetryCount` | int | `2` | 失败后重试次数（实际最大尝试次数 = RetryCount + 1） |
| `-RetryDelaySeconds` | int | `2` | 两次重试之间的等待秒数 |
| `-Parallel` | switch | 否 | 启用并行执行（基于 ThreadJob） |
| `-ThrottleLimit` | int | `6` | 并行模式下每批并发数量 |
| `-DryRun` | switch | 否 | 预演模式，仅显示将执行的命令而不实际运行 |
| `-LogDir` | string | 脚本目录下 `logs/` | 日志文件输出目录，不存在则自动创建 |
| `-ExcludePatterns` | string[] | 空 | 运行时追加的排除规则（通配符匹配相对路径） |
| `-MaxDepth` | int | `5` | 递归扫描的最大目录深度 |
| `-NoPause` | switch | 否 | 执行完毕后不等待用户按 Enter（适合脚本/CI 调用） |

### Mode 模式说明

| 模式 | 行为 |
|------|------|
| `All` | 先对所有仓库执行 checkout，再执行 pull |
| `CheckoutOnly` | 仅切换分支，不拉取 |
| `PullOnly` | 仅拉取，不切换分支（适合已在正确分支时使用） |

---

## 排除机制

脚本支持两层排除：

### 1. 内置默认排除

在脚本 `$defaultExcludePatterns` 中维护，可直接编辑：

```powershell
$defaultExcludePatterns = @(
    "BIM\ZwBm",
    "BIM\BmDb"
)
```

### 2. 运行时排除

通过 `-ExcludePatterns` 参数传入，与默认排除合并生效：

```powershell
.\git_recursive_checkout_pull.ps1 -ExcludePatterns "ThirdParty*","Test\MockRepo"
```

### 匹配规则

- 排除规则使用 PowerShell `-like` 通配符匹配
- 匹配目标是仓库相对于 `MainDir` 的**相对路径**
- 支持 `*`（任意字符）和 `?`（单字符）通配符
- 路径分隔符使用 `\`（Windows）

### 示例

假设目录结构：

```
MainDir/
├── BIM/
│   ├── ZwBm/       <- 被默认排除
│   ├── BmDb/       <- 被默认排除
│   └── Core/
├── Tools/
│   ├── BuildTool/
│   └── TestHelper/
└── ThirdParty/
    └── LibX/
```

- 排除 `"BIM\ZwBm"` → 匹配路径包含 `BIM\ZwBm` 的仓库
- 排除 `"ThirdParty*"` → 匹配路径包含 `ThirdParty` 开头的仓库
- 排除 `"*Tool*"` → 匹配路径包含 `Tool` 的所有仓库

---

## 使用示例

### 基本用法

```powershell
# 使用全部默认值（在 .\main 下扫描，checkout + pull developbim）
.\git_recursive_checkout_pull.ps1

# 指定目录和分支
.\git_recursive_checkout_pull.ps1 -MainDir "D:\projects\myapp" -Branch "master"

# 指定远程
.\git_recursive_checkout_pull.ps1 -MainDir "D:\work\main" -Remote "upstream" -Branch "develop"
```

### 模式控制

```powershell
# 只切换分支不拉取
.\git_recursive_checkout_pull.ps1 -Branch "feature/new-ui" -Mode CheckoutOnly

# 只拉取不切换分支（已在目标分支时使用）
.\git_recursive_checkout_pull.ps1 -Mode PullOnly

# 完整流程（默认）
.\git_recursive_checkout_pull.ps1 -Mode All
```

### 并行执行

```powershell
# 启用并行，默认 6 并发
.\git_recursive_checkout_pull.ps1 -Parallel

# 8 并发
.\git_recursive_checkout_pull.ps1 -Parallel -ThrottleLimit 8

# 小批量并发（网络较慢时）
.\git_recursive_checkout_pull.ps1 -Parallel -ThrottleLimit 3
```

### 排除仓库

```powershell
# 排除单个仓库
.\git_recursive_checkout_pull.ps1 -ExcludePatterns "Tools\BuildTool"

# 排除多个
.\git_recursive_checkout_pull.ps1 -ExcludePatterns "ThirdParty*","Test\MockRepo","*Deprecated*"
```

### 安全与调试

```powershell
# 模拟运行 — 查看会操作哪些仓库，不实际执行 git 命令
.\git_recursive_checkout_pull.ps1 -DryRun

# 浅层扫描（只看 2 层深度）
.\git_recursive_checkout_pull.ps1 -MaxDepth 2

# 增加重试（网络不稳定时）
.\git_recursive_checkout_pull.ps1 -RetryCount 5 -RetryDelaySeconds 5
```

### CI / 自动化环境

```powershell
# 不等待回车，适合脚本调用
.\git_recursive_checkout_pull.ps1 -MainDir "D:\work\main" -Branch "release/2.0" -Parallel -NoPause

# 配合退出码判断
.\git_recursive_checkout_pull.ps1 -NoPause
if ($LASTEXITCODE -ne 0) {
    Write-Error "部分仓库操作失败，请检查日志"
    exit 1
}
```

### 自定义日志位置

```powershell
.\git_recursive_checkout_pull.ps1 -LogDir "C:\logs\git_ops"
```

---

## 工作流程

```
1. 验证 MainDir 是否存在
2. 创建日志目录和日志文件
3. 递归扫描 MainDir，识别含 .git 的目录为仓库
   - 发现 .git 即标记为仓库，不再深入其子目录
   - 自动跳过 node_modules / .vs / .idea / __pycache__ 等目录
4. 应用排除规则过滤仓库列表
5. 根据 Mode 执行操作：
   - CheckoutOnly / All → git checkout <Branch>
   - PullOnly / All     → git pull --no-rebase <Remote> <Branch>
6. 失败时按 RetryCount 自动重试，间隔 RetryDelaySeconds
7. 输出汇总报告，写入日志文件
```

---

## 自动跳过的目录

递归扫描时自动跳过以下目录（不会深入扫描）：

- `node_modules`
- `.git`
- `__pycache__`
- `.vs`
- `.idea`

---

## 输出格式

### 状态图标

| 图标 | 颜色 | 含义 |
|------|------|------|
| `[+]` | 绿色 | 操作成功 |
| `[X]` | 红色 | 操作失败 |
| `[-]` | 黄色 | 已排除/跳过 |
| `[!]` | 黄色 | 警告（如重试中） |
| `[*]` | 白色 | 普通信息 |

### 输出示例

```
╔══════════════════════════════════════════════════════════════════════╗
║                      Git 批量 Checkout & Pull                       ║
╚══════════════════════════════════════════════════════════════════════╝

  主目录:     D:\work\main
  目标分支:   developbim
  远程:       origin
  模式:       All
  重试次数:   2
  重试间隔:   2s
  并行执行:   否
  最大深度:   5

── 扫描 Git 仓库 ──────────────────────────────────────────────────────

  发现 25 个 Git 仓库，排除 2 个，将处理 23 个

  [-] ZwBm                         排除: BIM\ZwBm
  [-] BmDb                         排除: BIM\BmDb

── Checkout -> developbim (23 个仓库) ─────────────────────────────────
  (1/23) [+] IMModeling                  checkout OK | Already on 'developbim'
  (2/23) [+] AppFx                       checkout OK | Switched to branch 'developbim'
  (3/23) [!] ZwTools                     checkout 失败 (第 1 次)，2s 后重试...
  (3/23) [+] ZwTools                     checkout OK | Switched to branch 'developbim'

── Pull origin/developbim (23 个仓库) ─────────────────────────────────
  (1/23) [+] IMModeling                  pull OK | Already up to date.
  (2/23) [+] AppFx                       pull OK | Updating 3a2b1c0..5d6e7f8

══════════════════════════════════════════════════════════════════════════

  汇总报告

    成功:   46
    失败:   0
    跳过:   2
    耗时:   01:23

  所有操作均已成功完成！

  日志: D:\work\main\logs\git_checkout_pull_20260526_103001.log

══════════════════════════════════════════════════════════════════════════
```

---

## 日志文件

### 位置

日志自动保存在 `LogDir` 目录下，文件名格式：

```
git_checkout_pull_YYYYMMDD_HHmmss.log
```

### 日志内容示例

```
[10:30:01] [INFO ] 开始执行 | 主目录=D:\work\main | 分支=developbim | 远程=origin | 模式=All | 并行=False | DryRun=False
[10:30:01] [INFO ] 发现 25 个仓库，排除 2 个，处理 23 个
[10:30:01] [WARN ] ZwBm | 排除: BIM\ZwBm
[10:30:02] [OK   ] IMModeling | checkout OK | Already on 'developbim'
[10:30:03] [OK   ] AppFx | checkout OK | Switched to branch 'developbim'
[10:30:15] [ERROR] ZwTools | pull 失败 (exit=1, 共尝试 3 次)
[10:31:05] [INFO ] 执行完毕 | 成功=44 | 失败=2 | 跳过=2 | 耗时=01:04
```

---

## 退出码

| 值 | 含义 |
|----|------|
| `0` | 所有操作成功 |
| `1` | 存在失败的仓库，或未找到任何仓库 |

可在脚本/CI 中通过 `$LASTEXITCODE` 获取。

---

## 适配其他项目

此脚本不依赖任何硬编码仓库列表，可直接用于任意多仓库项目。如需定制：

1. **修改默认分支**：更改参数默认值 `$Branch = "developbim"` 为你的分支名
2. **修改默认排除**：编辑脚本中 `$defaultExcludePatterns` 数组
3. **修改默认主目录**：更改 `$MainDir` 默认值

### 支持的目录结构

```
# 扁平结构
MainDir/repo1/.git
MainDir/repo2/.git

# 嵌套分组
MainDir/group1/repo1/.git
MainDir/group2/repo2/.git

# 混合深度
MainDir/repo1/.git
MainDir/group/subgroup/repo2/.git

# 以上所有结构均可自动识别
```

---

## 常见问题

### Q: 并行模式报错 "Start-ThreadJob 不可用"

安装 ThreadJob 模块：

```powershell
Install-Module -Name ThreadJob -Scope CurrentUser
```

或者不使用 `-Parallel` 参数，脚本会自动顺序执行。

### Q: 某些仓库没有目标分支怎么办？

脚本会报告 checkout 失败，该仓库的 pull 仍会尝试执行（Mode=All 时）。建议先用 `-DryRun` 确认仓库列表，或用 `-ExcludePatterns` 排除不相关的仓库。

### Q: 如何只查看会操作哪些仓库？

```powershell
.\git_recursive_checkout_pull.ps1 -DryRun
```

### Q: 网络不好导致 pull 经常失败？

增加重试次数和间隔：

```powershell
.\git_recursive_checkout_pull.ps1 -RetryCount 5 -RetryDelaySeconds 10
```

### Q: 如何在脚本中调用而不阻塞？

```powershell
.\git_recursive_checkout_pull.ps1 -NoPause
```
