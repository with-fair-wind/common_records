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

## VS Code / Cursor 扩展脚本（Generate / Download / Install）

这三套脚本组成了一个完整的扩展管理流程：`生成清单 -> 下载离线包 -> 批量安装`。  
适合以下场景：

- 新机器快速恢复开发环境
- Cursor / VS Code 分别维护不同扩展集合
- 内网或离线环境提前准备 `.vsix`

### 1) Generate-Extensions.ps1

作用：从 `extensions.json` 读取已安装扩展，生成两个清单文件：

- `extensions-cursor.txt`
- `extensions-vscode.txt`

详细说明：

- 自动读取 `extensions.json`，提取每项的 `identifier.id`
- 对扩展 ID 去重、排序
- 根据内置排除规则（如 Remote/Jupyter/Copilot 等）筛出 Cursor 建议清单
- VS Code 清单保留全量扩展

参数：

- `-JsonPath`：手动指定 `extensions.json` 路径（可选）

路径解析顺序：

1. 若传入 `-JsonPath`，优先使用该路径
2. `D:\scoop\apps\vscode\current\data\extensions\extensions.json`
3. `%USERPROFILE%\.vscode\extensions\extensions.json`

示例：

```powershell
# 自动找路径（优先 Scoop）
pwsh .\Generate-Extensions.ps1

# 手动指定 JSON
pwsh .\Generate-Extensions.ps1 -JsonPath "D:\scoop\apps\vscode\current\data\extensions\extensions.json"
```

### 2) Download-Extensions.ps1

作用：按清单或 JSON 从 Marketplace 下载最新 `.vsix` 文件到本地。

详细说明：

- 支持三种模式：`cursor`、`vscode`、`json`
- 下载目录按模式隔离：`.\vsix\cursor`、`.\vsix\vscode`、`.\vsix\json`
- 若目标文件已存在会自动跳过
- 单个扩展下载失败不影响后续扩展

参数：

- `-Mode`：`cursor | vscode | json`（默认 `cursor`）
- `-JsonPath`：手动指定 `extensions.json` 路径（可选）

模式行为：

- `cursor`：优先使用 `extensions-cursor.txt`，不存在则从 JSON 动态筛选
- `vscode`：优先使用 `extensions-vscode.txt`，不存在则直接读取 JSON
- `json`：直接读取 JSON，不区分 Cursor / VS Code

示例：

```powershell
# 下载 Cursor 清单对应扩展
pwsh .\Download-Extensions.ps1 -Mode cursor

# 下载 VS Code 清单对应扩展
pwsh .\Download-Extensions.ps1 -Mode vscode

# 直接从 JSON 下载（不区分编辑器）
pwsh .\Download-Extensions.ps1 -Mode json -JsonPath "D:\scoop\apps\vscode\current\data\extensions\extensions.json"
```

### 3) Install-VSCodeExtensions.ps1

作用：从清单文件读取扩展 ID，调用 `code` 或 `cursor` 批量安装。

详细说明：

- 不再维护脚本内硬编码扩展数组
- 默认按模式自动选择清单文件
- 支持手动指定清单路径和安装命令
- 输出安装进度和失败列表

参数：

- `-Mode`：`cursor | vscode`（默认 `vscode`）
- `-ListPath`：手动指定扩展清单文件（可选）
- `-CodeCmd`：手动指定安装命令（可选，示例：`code` / `cursor`）

默认规则：

- `-Mode vscode`：默认读取 `extensions-vscode.txt`，默认命令 `code`
- `-Mode cursor`：默认读取 `extensions-cursor.txt`，默认命令 `cursor`

示例：

```powershell
# 安装 VS Code 清单扩展
pwsh .\Install-VSCodeExtensions.ps1 -Mode vscode

# 安装 Cursor 清单扩展
pwsh .\Install-VSCodeExtensions.ps1 -Mode cursor

# 强制指定清单和命令
pwsh .\Install-VSCodeExtensions.ps1 -Mode cursor -ListPath ".\extensions-cursor.txt" -CodeCmd "cursor"
```

### 推荐使用流程

#### 在线环境（推荐）

1. 生成清单：
   `pwsh .\Generate-Extensions.ps1`
2. 按目标编辑器安装：
   - VS Code：`pwsh .\Install-VSCodeExtensions.ps1 -Mode vscode`
   - Cursor：`pwsh .\Install-VSCodeExtensions.ps1 -Mode cursor`

#### 离线 / 内网环境

1. 在可联网机器生成清单：
   `pwsh .\Generate-Extensions.ps1`
2. 下载离线包：
   - `pwsh .\Download-Extensions.ps1 -Mode vscode`
   - `pwsh .\Download-Extensions.ps1 -Mode cursor`
3. 将 `vsix` 目录拷贝到目标机器，再使用本地 `.vsix` 安装（可另写离线安装脚本）

### 建议

- 建议先执行 `Generate`，确保清单与当前机器实际扩展一致
- 建议将 `extensions-cursor.txt` 与 `extensions-vscode.txt` 纳入版本管理
- 若安装命令不存在，先确认 `code` 或 `cursor` 已加入环境变量
