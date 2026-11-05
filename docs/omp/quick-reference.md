# omp 日常速查：配置、命令与快捷键

这里的 omp 指 **oh-my-pi AI 编码代理**。本文面向 Windows / PowerShell，依据本机 `omp/18.16.0`（2026-11-05）的帮助、安装包文档、配置及键位定义核对。

- [常用配置](#常用配置)：文件位置、模型、审批、外观与项目覆盖。
- [常用命令](#常用命令)：PowerShell 启动命令和会话内斜杠命令。
- [常用操作快捷键](#常用操作快捷键)：输入、模型、审批、会话和子代理。
- [自定义快捷键](#自定义快捷键)：为新会话、恢复会话等操作绑定按键。
- [排查与维护](#排查与维护)：Windows 按键冲突和升级核对入口。

## 常用配置

### 文件位置与配置范围

`~` 指用户主目录，PowerShell 中可用 `$env:USERPROFILE` 表示。

| 用途 | 默认位置 | 修改方式 |
| --- | --- | --- |
| 用户设置 | `~/.omp/agent/config.yml` | `/settings` 或 `omp config set`；已有 `config.yaml` 时沿用它 |
| 项目设置 | `<启动目录>/.omp/config.yml` | 手动编辑，只影响该项目 |
| 快捷键 | `~/.omp/agent/keybindings.yml` | 手动编辑，独立于 `config.yml` |
| 自定义模型端点 | `~/.omp/agent/models.yml` | 手动编辑；内置模型通过登录和模型选择器配置即可 |
| 用户指令 | `~/.omp/agent/AGENTS.md` | 跨项目通用约定 |
| omp 项目指令 | `<项目>/.omp/AGENTS.md` | 项目约定；与项目设置的发现规则不同 |

用 `omp config path` 确认当前 agent 目录。`--profile work` 将用户设置、凭据和会话等切到 `~/.omp/profiles/work/agent/`；快捷键先继承默认 profile，再按动作覆盖。

项目设置取**进程启动目录**下的 `.omp/`，不会向父目录查找。请从项目根目录启动，或用 `omp --cwd 'D:\code\your-project'`。

### 查看、修改与恢复

在 **PowerShell** 中执行：

```powershell
omp config path                            # agent 目录，不是配置文件路径
omp config list                            # 全部设置及当前生效值
omp config get defaultThinkingLevel        # 查看单项
omp config list --scope global --json       # 用户层实际写入的项
omp config list --scope project --json      # 项目层实际写入的项

omp config set defaultThinkingLevel high
omp config set tools.approvalMode write
omp config set theme.dark titanium
omp config set tui.vimMode true             # 可选：Vim 输入模式
omp config reset tui.vimMode                # 删除用户层覆盖，回退到其他层或默认值
```

`config set/reset` 和 `/settings` 通常写**用户层**，不会因为在项目目录执行就写项目文件；`--scope` 仅用于 `config list`。项目覆盖请编辑 `.omp/config.yml`。模型选择器在 `modelRoleStorage: project` 时只将角色分配写入项目层。

优先级从高到低：设置专用环境变量 → 本次运行覆盖 → `--config` 覆盖文件 → 项目设置 → 用户设置 → 内置默认。对象深合并，数组整体替换；`reset` 不会删除项目层覆盖。

### 常用设置

| 配置键 | 用途与常见取值 |
| --- | --- |
| `modelRoles` | 分配 `default`、`smol`、`slow`、`plan` 等模型角色；优先用 `Alt+M` 配置 |
| `modelRoleStorage` | 角色保存到 `global`（用户）或 `project`（项目） |
| `defaultThinkingLevel` | 如 `medium`、`high`、`auto`；可用推理档位受模型能力限制 |
| `tools.approvalMode` | 工具审批模式，见下表 |
| `tools.approval` | 单工具策略对象，值为 `allow`、`prompt`、`deny` |
| `theme.dark` / `theme.light` | 暗色 / 亮色主题，也可用 `/theme` |
| `symbolPreset` | `unicode`、`nerd`、`ascii`；缺字时可试 `ascii` |
| `compaction.enabled` | 自动压缩上下文，通常保持 `true` |
| `compaction.thresholdPercent` | 触发上下文维护的百分比，如 `80`；`-1` 使用默认预留策略 |
| `tui.vimMode` | 输入框的 Vim 模式，默认关闭 |
| `enabledProviders` | 按需启用其他工具的用户级配置发现，如 `codex`、`claude` |

审批按工具能力等级判断：

| 模式 | 行为 |
| --- | --- |
| `always-ask` | 只读工具自动通过；写入和执行工具询问 |
| `always-ask-cached` | 写入、执行和未授权文件读取会询问，可记住文件或目录授权 |
| `write` | 读取与工作区写入自动通过；执行工具询问 |
| `yolo` | 各能力等级自动通过；显式工具策略仍可要求询问或拒绝 |

18.16.0 的内置审批默认值为 `yolo`。若希望执行命令前确认，可显式设为 `write`；连文件修改也要确认则用 `always-ask`。

### 可按需合并的配置示例

将需要的项合并到用户 `config.yml`，保留已有其他配置。以下是个人选择示例，**不代表全部内置默认值**：

```yaml
defaultThinkingLevel: high

tools:
  approvalMode: write

theme:
  dark: titanium
  light: light
symbolPreset: unicode

compaction:
  enabled: true
  thresholdPercent: 80

tui:
  vimMode: false
```

模型先用 `omp login` 登录，用 `omp models` 查可用项，再在会话内按 `Alt+M` 分配角色。手写时按下面结构合并，先将占位符替换为可用的完整 `provider/model-id`：

```yaml
modelRoles:
  default: <日常模型的完整 ID>
  smol: <快速模型的完整 ID>
  slow: <复杂任务模型的完整 ID>
  plan: <规划模型的完整 ID>
```

例如，项目需要更严格的审批，就在项目 `.omp/config.yml` 中写：

```yaml
tools:
  approvalMode: always-ask
```

仅本次启动需要覆盖时，在 PowerShell 中执行：

```powershell
omp --model '<provider/model-id>'           # 替换为实际模型 ID
omp --thinking high
omp --approval-mode always-ask
omp --config .\omp-local.yml               # 额外 YAML 覆盖层，不写回用户设置
omp --profile work                         # 隔离的配置、凭据和会话
```

## 常用命令

### PowerShell 中执行

| 场景 | 命令 | 说明 |
| --- | --- | --- |
| 首次初始化 / 登录 | `omp setup`、`omp login` | 引导配置、可选依赖和模型提供商登录 |
| 查看 / 搜索模型 | `omp models`、`omp models find <关键词>` | 获取可用模型 ID |
| 启动交互会话 | `omp` | 在当前项目启动 |
| 带任务启动 | `omp '解释项目的入口与构建流程'` | 首条消息直接作为任务 |
| 附带文件 | `omp '@README.md' '概括项目结构'` | `@路径` 作为附件；PowerShell 中加引号避免语法歧义 |
| 继续上次会话 | `omp -c` | 优先当前终端关联且符合目录条件的会话 |
| 选择 / 指定历史会话 | `omp -r`、`omp --resume <id或路径>` | 无参数打开选择器；ID 支持前缀 |
| 恢复中断任务 | `omp --restore` | 恢复并继续遗留回合与子代理；普通续聊用 `-c` / `-r` |
| 单次输出后退出 | `omp -p '总结最近一次提交'` | 非交互执行 |
| 接收管道文本 | `git diff --cached \| omp -p '审查这些暂存改动'` | stdin 作为任务上下文 |
| 限制任务时长 | `omp -p --max-time 10m '检查构建问题'` | 为非交互任务设置时间上限 |
| 版本 / 更新 | `omp --version`、`omp update` | 升级后重新核对常用设置和键位 |
| 查看帮助 | `omp --help`、`omp config --help` | 以当前版本实际支持的参数为准 |

`<…>` 是占位符，执行前替换。`--restore` 仅用于交互模式，不附带新的任务提示。

### omp 会话内输入

这些是 **TUI 输入框中的斜杠命令**，不要直接放到 PowerShell 执行。

| 场景 | 命令 | 作用 |
| --- | --- | --- |
| 配置 / 快捷键 / 主题 | `/settings`、`/hotkeys`、`/theme` | 打开相应面板 |
| 查看模型 | `/model` | 查看当前模型选择并按界面操作 |
| 本会话切模型 | `/switch [模型]` | 临时切换，不改角色配置 |
| 推理力度 | `/effort [级别]` | 查看或设置当前推理力度 |
| 新会话 / 恢复 | `/new`、`/resume [id]` | 开新对话 / 恢复历史，无 ID 时打开选择器 |
| 会话命名 | `/rename 项目构建排查` | 方便之后搜索 |
| 分叉 / 会话树 | `/fork`、`/tree` | 分叉当前会话 / 浏览分支 |
| 上下文 / 压缩 | `/context`、`/compact` | 查看占用 / 压缩长会话，可附带关注点 |
| 重试失败回合 | `/retry` | 也可直接按 `F5` |
| 工具 / 用量 | `/tools`、`/usage` | 查看可用工具 / 账号用量 |
| 后台作业 | `/jobs`、`/jobs kill <id>` | 查看 / 取消指定作业 |
| 独立旁问 | `/btw 问题` | 围绕当前会话提问，不打断主回合 |
| 导出会话 | `/export` | 导出 HTML，不会自动脱敏 |
| MCP / 插件 | `/mcp list`、`/mcp reload`、`/reload-plugins` | 查看 MCP / 重载 MCP / 重载插件 |
| 生成项目约定 | `/init` | 为代码库生成 AGENTS.md |

日常流程：`omp -r` 找历史会话 → `/rename` 命名 → `Alt+P` 选模型 → `Alt+Shift+P` 进入规划 → 确认后执行 → `/context` 查占用，过长时 `/compact`。

## 常用操作快捷键

以下是 **18.16.0 默认键位**，未启用 Vim 输入模式时适用。面板有独立键位；优先看当前面板提示。用户重映射后，以 `/hotkeys` 和实际提示为准。

### 输入、编辑与消息

| 操作 | 默认快捷键 | 说明 |
| --- | --- | --- |
| 发送消息 | `Enter` | 空闲时开始回合；运行中普通消息作为 steering，在可处理时插入当前任务 |
| 输入换行 | `Shift+Enter` 或 `Ctrl+J` | Windows 下前者不生效时用后者 |
| 补全命令 / 路径 | `Tab` | 先输入 `/` 或 `@` 再补全 |
| 排队后续任务 | `Ctrl+Q` 或 `Ctrl+Enter` | follow-up 在当前回合结束后处理；审批面板中同键用于批准 |
| 取回排队消息 | `Alt+↑` 或 `Shift+↑` | 放回输入框编辑 |
| 搜索提示词历史 | `Ctrl+R` | 与 `/resume` 搜索会话不同 |
| 召回输入历史 | `↑` / `↓` | 多行输入时也用于行间移动 |
| 外部编辑器写长提示 | `Ctrl+G` | 使用 `VISUAL` / `EDITOR` 指定的编辑器 |
| 复制当前行 / 整段提示 | `Alt+Shift+L` / `Alt+Shift+C` | 复制输入框文本 |
| 粘贴图片，文本回退 | Windows：`Ctrl+V` 或 `Alt+V` | Windows Terminal 优先试 `Alt+V` |
| 原样粘贴文本 | `Ctrl+Shift+V` 或 `Alt+Shift+V` | 不折叠为大段粘贴块；被终端拦截时用后者 |
| 行首 / 行尾 | `Home` / `End` 或 `Ctrl+A` / `Ctrl+E` | 输入框内移动 |
| 向前删一个词 | `Ctrl+Backspace` 或 `Ctrl+W` | 删除光标前的词 |
| 删除到行首 / 行尾 | `Ctrl+U` / `Ctrl+K` | 删除当前行的一部分 |
| 撤销输入编辑 | `Ctrl+-` 或 `Ctrl+_` | 默认编辑器撤销键 |
| 清空未发送草稿 | `Ctrl+C` | 可用 `↑` 召回；连续两次 `Ctrl+C` 会退出 |
| 退出 omp | 空输入框时 `Ctrl+D` | 非空时默认作为向前删除字符 |

配合 Neovim：启动 omp 前在 PowerShell 设置 `$env:EDITOR = 'nvim'`，再用 `Ctrl+G` 编辑长提示；该环境变量只影响当前 PowerShell 及之后启动的子进程。

### 模型、推理与规划

| 操作 | 默认快捷键 | 说明 |
| --- | --- | --- |
| 本会话临时选模型 | `Alt+P` | 日常切换最直接，不改角色配置 |
| 选模型并分配角色 | `Alt+M` | 按 `modelRoleStorage` 保存角色 |
| 循环模型 | `Ctrl+P` / `Ctrl+Shift+P` | 向前 / 向后；默认角色顺序 `smol` → `default` → `slow`，可用 `--models` 指定列表 |
| 调整推理力度 | `Shift+Tab` | 在模型支持的档位间循环 |
| 显示 / 隐藏思考块 | `Ctrl+T` | 仅改变显示，不关闭模型推理 |
| 进入 / 退出规划模式 | `Alt+Shift+P` | 规划阶段只读，按界面提示审批计划 |

### 运行、工具输出与审批

| 操作 | 默认快捷键 | 适用位置 |
| --- | --- | --- |
| 中断当前操作 | `Esc` | 主聊天；打开面板时先由面板处理 |
| 重试失败回合 | `F5` 或 `Alt+R` | 上一回合失败后 |
| 展开 / 折叠工具输出 | `Ctrl+O` | 主界面；审批面板可展开详情 |
| 显示 / 隐藏工具活动 | `Ctrl+Shift+O` | 主界面，可能被终端绑定占用 |
| 直接批准工具调用 | `Ctrl+Q` 或 `Ctrl+Enter` | **存在待审批工具调用时** |
| 拒绝工具调用 | `Esc` | 工具审批面板 |
| 执行选中的审批选项 | 方向键选择后 `Enter` | 审批面板，选中“批准”时会批准 |
| 收起 / 恢复待回答问题 | `Alt+H` | ask 问题面板；恢复也可用 `Enter` |
| 重置终端显示 | `Alt+L` | 显示错乱时；`Ctrl+L` 默认用于 live 语音 |

### 会话选择器与子代理

| 场景 | 操作 | 按键 |
| --- | --- | --- |
| `/resume` 或 `omp -r` | 选择 / 打开 / 取消 | `↑` `↓`、`Enter`、`Esc` |
| 会话选择器 | 当前项目 / 全部项目切换 | `Tab` |
| 会话选择器 | 搜索 | 直接输入标题、ID、目录或消息关键词 |
| 会话选择器 | 固定 / 取消固定所选会话 | `Alt+K` / `Alt+Shift+K` |
| 会话选择器 | 删除会话，需确认 | `Delete`；搜索框为空时也可用 `Backspace` |
| 主界面 | 打开 / 关闭 Agent Hub | `Alt+A` |
| Agent Hub | 选择代理 / 查看其会话 | `↑` `↓` 或 `j` `k` / `Enter` |
| Agent Hub | 切换 Agents / Activity | `1` / `2` |
| Agent Hub | 清过滤 / 关闭 | `Esc`，按当前状态逐层返回 |
| 已聚焦子代理会话 | 返回主会话 | 空输入框时 `Esc`；此处不会中断子代理 |

新会话、恢复、分叉和会话树在本版本**默认没有专用快捷键**，可用 `/new`、`/resume`、`/fork`、`/tree`，也可自行绑定。

## 自定义快捷键

编辑 `~/.omp/agent/keybindings.yml`，使用 profile 时也可编辑其同名文件。格式是“动作 ID → 按键或按键数组”，**不要写进 `config.yml`，不要套一层 `keybindings:`**。

下面是可选映射，新增会话管理按键，并保留 Windows 备用键：

```yaml
# 以下四个是自定义示例，不是默认键位。
app.session.new: Alt+N
app.session.resume: Alt+S
app.session.fork: Alt+Shift+F
app.session.tree: Alt+T

# 同一动作可以有多个按键。
app.message.followUp: [Ctrl+Q, Ctrl+Enter]
app.clipboard.pasteImage: [Alt+V, Ctrl+V]

# 可选：禁用按住空格语音输入。
app.stt.pushToTalk: []
```

按键名称不区分大小写，`[]` 禁用动作。删除一项恢复默认绑定；若来自默认 profile，则恢复继承。保存后重新启动 omp，用 `/hotkeys` 检查。终端先拦截的按键需要修改终端绑定或换键。

启用 `tui.vimMode` 后，输入框从 Insert 开始，`Esc` 先进入 Normal；`i` / `a` 回到输入，`h/j/k/l` 移动，`w/b` 按词移动，`dd` 删行，`u` 撤销，`v` 选区。此时不要将第一次 `Esc` 当作中断任务，按模式和界面提示操作。

## 排查与维护

| 现象 | 优先处理 |
| --- | --- |
| `Ctrl+Enter` 无效 | Windows Terminal 不提供可区分的该按键事件，改用 `Ctrl+Q` |
| `Ctrl+V` 没贴上图片 | 改用 `Alt+V`；确认剪贴板包含图片而非仅有文件列表 |
| `Shift+Enter` 变成发送 | 用 `Ctrl+J` 换行 |
| `Ctrl+Shift+V` / `Ctrl+Shift+O` 无效 | 检查 Windows Terminal 的 Actions / 操作绑定；原样粘贴可用 `Alt+Shift+V` |
| 配置修改没效果 | `config path` 确认 profile，`config get` 查生效值，再检查项目、CLI、环境变量覆盖 |
| 找不到项目配置 | 从项目根目录启动，项目设置不会向上查找 `.omp/config.yml` |
| `Ctrl+G` 打不开编辑器 | 确认 `VISUAL` / `EDITOR` 设置且程序在 PATH 中，可先运行 `nvim` 验证 |
| 会话太长 | `/context` 看占用，再 `/compact`；新任务用 `/new` |

本仓库只维护这份常用速查，不再保存全量自动附录或定时生成文档。若以前注册过旧的 `Update-OmpDoc` Windows 计划任务，可在“任务计划程序”核对它确实指向本仓库旧脚本后，停用或删除；删除脚本不会自动注销系统任务。

升级后检查 `omp --version`、`omp --help`、`omp config list` 和会话内 `/hotkeys`，按变化修订本文。完整机制按需查官方资料：

- [CLI 参考](https://github.com/can1357/oh-my-pi/blob/main/docs/cli-reference.md)
- [设置与配置读写](https://github.com/can1357/oh-my-pi/blob/main/docs/settings.md)
- [快捷键与 Vim 输入](https://github.com/can1357/oh-my-pi/blob/main/docs/keybindings.md)
- [审批模式](https://github.com/can1357/oh-my-pi/blob/main/docs/approval-mode.md)
- [会话选择与恢复](https://github.com/can1357/oh-my-pi/blob/main/docs/session-switching-and-recent-listing.md)
- [Agent Hub](https://github.com/can1357/oh-my-pi/blob/main/docs/agent-hub.md)

也可在 omp 中让代理读取 `omp://keybindings.md`、`omp://settings.md` 或 `omp://cli-reference.md` 查询当前安装包说明；在线 `main` 文档可能领先于已安装版本。
