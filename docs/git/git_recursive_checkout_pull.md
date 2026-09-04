# git_recursive_checkout_pull.ps1 使用文档

## 1. 脚本职责

`git_recursive_checkout_pull.ps1` 用于在指定目录中安全地批量同步多个 Git 仓库：

- 主仓库使用命令行参数指定的目标分支。
- 已初始化的子模块优先使用直接父仓库 `.gitmodules` 中声明的分支。
- 未声明子模块分支时，回退到主仓库目标分支。
- 可选择同时处理目录树中的独立嵌套仓库，或者只处理主仓库和正式子模块。
- 父仓库成功后才处理其子模块；checkout 失败后不会继续 pull。
- 输出终端汇总、日志和可供自动化调用的退出码。

该脚本执行的是“按分支 checkout/pull”，不是 `git submodule update` 的替代品。

## 2. 不负责的功能

脚本不会：

- 克隆主仓库。
- 初始化未初始化的子模块。
- 按父仓库记录的 gitlink commit 检出子模块。
- 自动创建远程分支。
- 自动 stash、commit、reset 或丢弃本地修改。
- 自动解决 checkout、merge 或 pull 冲突。
- 删除失效的子模块目录。

本地修改阻止 checkout 或 pull 时，操作会失败并保留现场。

## 3. 环境要求

| 依赖 | 要求 |
|---|---|
| PowerShell | PowerShell 7.0+；不支持 Windows PowerShell 5.x |
| Git | 已安装并加入 `PATH` |
| ThreadJob | 仅并行模式需要；不可用时自动回退顺序执行 |
| PSScriptAnalyzer | 仅开发检查需要；已验证 1.25.0 |
| Pester | 仅集成测试需要；要求 5.6.1+，已验证 6.1.0 |

## 4. 参数

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `-MainDir` | string | 当前目录下的 `main` | 扫描根目录；如果它本身是 Git 仓库，则作为主仓库 |
| `-Branch` | string | `developbim` | 主仓库和独立仓库的目标分支，也是子模块分支回退值 |
| `-Remote` | string | `origin` | 远程仓库名称 |
| `-Mode` | enum | `All` | `All`、`CheckoutOnly` 或 `PullOnly` |
| `-RetryCount` | int | `2` | 远端检查和 fetch 的重试次数；最大尝试次数为此值加一 |
| `-RetryDelaySeconds` | int | `2` | 重试间隔秒数 |
| `-Parallel` | switch | 否 | 并行处理同一层级、互不依赖的仓库 |
| `-ThrottleLimit` | int | `6` | 并行批次大小，必须大于零 |
| `-DryRun` | switch | 否 | fetch 并生成执行计划，但不 checkout 或 pull |
| `-LogDir` | string | 脚本目录下的 `logs` | 日志目录，不存在时自动创建 |
| `-ExcludePatterns` | string[] | 空 | 追加路径排除规则 |
| `-MaxDepth` | int | `5` | 文件系统递归扫描深度 |
| `-SubmodulesOnly` | switch | 否 | 跳过非主仓库、非子模块的独立仓库 |
| `-NoPause` | switch | 否 | 完成后不等待 Enter，适用于 CI 或其他脚本调用 |

数值参数会在绑定阶段校验：重试次数、间隔和深度不能为负数，并发数必须大于零。

## 5. 仓库发现与分类

脚本从 `MainDir` 开始扫描当前已经存在的 `.git` 目录或文件，并分类为：

| 类型 | 判定方式 | 分支规则 |
|---|---|---|
| `Main` | 仓库路径等于 `MainDir` | 使用 `-Branch` |
| `Submodule` | Git 报告了直接 superproject，并且该父仓库位于扫描根目录内 | 读取父仓库 `.gitmodules` |
| `Standalone` | 位于目录树中，但不是 Git 子模块 | 使用 `-Branch` |

扫描会跳过以下普通目录：

- `node_modules`
- `.git`
- `__pycache__`
- `.vs`
- `.idea`

内置排除项为：

```powershell
BIM\ZwBm
BIM\BmDb
```

`-ExcludePatterns` 会追加到内置规则。规则通过 PowerShell `-like` 对仓库相对路径执行包含式匹配。

示例：

```powershell
.\git_recursive_checkout_pull.ps1 `
    -MainDir "D:\work\main" `
    -ExcludePatterns "ThirdParty*","Tests\MockRepo"
```

### SubmodulesOnly

启用 `-SubmodulesOnly` 后：

- 主仓库继续处理。
- 已初始化的子模块继续处理。
- 独立嵌套仓库被跳过，其子模块也会一并按正常跳过处理（父仓库未同步，不再解析其目标版本）。
- 父仓库目标版本中已移除的子模块被跳过。

脚本不会初始化只登记在 `.gitmodules`、但本地尚未形成 Git 仓库的子模块。

## 6. 子模块目标分支

子模块根据直接父仓库的目标版本解析 `.gitmodules`。

给定：

```ini
[submodule "render-engine"]
    path = components/render
    branch = release
```

脚本先根据 `path = components/render` 找到配置节名称 `render-engine`，再读取：

```text
submodule.render-engine.branch
```

因此子模块名称不要求与路径相同。

完整规则如下：

| `.gitmodules` 状态 | 子模块目标分支 | 汇总来源 |
|---|---|---|
| `branch = release` | `release` | `.gitmodules` |
| `branch = .` | 父仓库的目标分支 | `branch = .` |
| 未配置 `branch` | `-Branch` 参数 | 回退参数 |
| 目标版本未登记该路径 | 不再处理该仓库 | 跳过 |

嵌套子模块会逐层解析，因此第二层子模块读取的是第一层父仓库目标版本中的 `.gitmodules`。

## 7. 执行模式

### All

每个仓库先 checkout，成功后才 pull：

```text
主仓库 checkout
└── 主仓库 pull
    └── 第一层子模块 checkout → pull
        └── 第二层子模块 checkout → pull
```

安全约束：

- checkout 失败后，同一仓库的 pull 标记为依赖失败，不再执行。
- 父仓库未成功完成时，子模块及其后代均不执行。
- 远端分支不存在但本地分支存在时，仍可 checkout 本地分支，pull 被跳过。
- 远端和本地都没有目标分支时，checkout 与 pull 均按正常跳过处理，不计入失败。

### CheckoutOnly

只执行分支切换：

```powershell
.\git_recursive_checkout_pull.ps1 -Mode CheckoutOnly
```

本地没有分支但远端存在时，从远端创建跟踪分支。

### PullOnly

只拉取更新：

```powershell
.\git_recursive_checkout_pull.ps1 -Mode PullOnly
```

脚本会先检查当前分支是否与目标分支完全一致。分支不一致或处于 detached HEAD 时拒绝 pull，防止把目标分支合并进错误的当前分支。

## 8. 远端分支检查与重试

每次操作会：

1. 验证目标分支名。
2. 检查指定远程是否存在。
3. 使用 `git ls-remote --heads` 查询远端真实分支。
4. 显式 fetch 目标分支到对应的远程跟踪引用。
5. 执行 checkout 或 pull。

该检查不依赖本地是否已经存在 `refs/remotes/<remote>/<branch>`，因此兼容单分支克隆和受限 fetch refspec。

`RetryCount` 只应用于可能暂时恢复的远端查询和 fetch。checkout 与 pull 不自动重试，避免在冲突或部分合并状态下重复执行。

## 9. 并行处理

启用方式：

```powershell
.\git_recursive_checkout_pull.ps1 -Parallel -ThrottleLimit 6
```

并行只发生在同一层级的仓库之间。父仓库与子模块永远不会并行。

顺序和并行模式调用同一个 Git 工作单元，因此具有相同的：

- 分支验证。
- 远端查询。
- checkout/pull 安全规则。
- 结果状态。

如果 `Start-ThreadJob` 不可用，脚本会输出警告并回退到顺序模式。

## 10. DryRun

```powershell
.\git_recursive_checkout_pull.ps1 -DryRun -NoPause
```

DryRun 会执行以下只影响 Git 元数据的操作：

- 查询远程分支。
- fetch 目标分支并更新远程跟踪引用。
- 从目标引用读取 `.gitmodules`。

DryRun 不会：

- checkout 分支。
- 修改 HEAD。
- 修改工作树。
- 执行 pull 或 merge。

允许 fetch 是为了确保 DryRun 解析出的子模块分支与真实执行一致。

## 11. 状态、日志与退出码

终端状态标记：

| 标记 | 含义 |
|---|---|
| `[+]` | 操作成功 |
| `[~]` | DryRun 计划 |
| `[-]` | 正常跳过或排除 |
| `[D]` | 因父仓库或前置操作失败而跳过 |
| `[X]` | 操作失败 |
| `[!]` | 系统警告 |

汇总报告包括：

- 成功操作数。
- DryRun 计划数。
- 失败数。
- 正常跳过数。
- 依赖跳过数。
- 子模块分支来源统计。
- 失败仓库及操作阶段。

退出码：

| 退出码 | 含义 |
|---|---|
| `0` | 没有 Git 操作失败；允许存在正常跳过与依赖跳过项 |
| `1` | 至少一个 Git 操作失败、所有仓库均被跳过而未执行任何操作，或 PowerShell 参数绑定/运行时错误 |
| `2` | 脚本预检发现 Git 不可用、主目录不存在或没有发现仓库 |

## 12. 常用示例

处理主仓库、子模块和独立嵌套仓库：

```powershell
.\git_recursive_checkout_pull.ps1 `
    -MainDir "D:\work\main" `
    -Branch developbim `
    -NoPause
```

只处理主仓库及子模块：

```powershell
.\git_recursive_checkout_pull.ps1 `
    -MainDir "D:\work\main" `
    -Branch developbim `
    -SubmodulesOnly `
    -NoPause
```

并行执行：

```powershell
.\git_recursive_checkout_pull.ps1 `
    -MainDir "D:\work\main" `
    -Parallel `
    -ThrottleLimit 8 `
    -NoPause
```

检查执行计划：

```powershell
.\git_recursive_checkout_pull.ps1 `
    -MainDir "D:\work\main" `
    -DryRun `
    -NoPause
```

仅拉取已经位于正确分支的仓库：

```powershell
.\git_recursive_checkout_pull.ps1 `
    -MainDir "D:\work\main" `
    -Mode PullOnly `
    -NoPause
```

## 13. 建议的执行流程

首次在真实仓库树中使用时，建议先执行：

```powershell
.\git_recursive_checkout_pull.ps1 -DryRun -SubmodulesOnly -NoPause
```

确认以下信息后再执行真实操作：

- 主仓库目标分支正确。
- 子模块名称、路径和分支来源正确。
- 没有意外纳入的独立仓库。
- 没有当前分支不匹配或远端缺失错误。

然后移除 `-DryRun`：

```powershell
.\git_recursive_checkout_pull.ps1 -SubmodulesOnly -NoPause
```

## 14. 开发检查

仓库提供了 `PSScriptAnalyzerSettings.psd1`，其中仅排除两项有意设计：

- 终端状态界面需要彩色 `Write-Host`。
- 脚本只支持 PowerShell 7，因此使用 UTF-8 无 BOM。

运行静态检查：

```powershell
Invoke-ScriptAnalyzer `
    -Path . `
    -Recurse `
    -Settings .\PSScriptAnalyzerSettings.psd1
```

运行集成测试：

```powershell
Invoke-Pester .\tests\git_recursive_checkout_pull.Tests.ps1
```
