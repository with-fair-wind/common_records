# Neovim 与 LazyVim 使用、配置及 C++ 开发说明

本文面向第一次把 Neovim 用作开发环境的 Windows 用户。先学习官方 LazyVim 的基本操作，再理解本仓库的多机部署定制。安装操作、编辑器配置和项目构建分别说明。

核查日期：2026-10-13。资料通过 Context7 检索 Neovim、LazyVim 和 lazy.nvim 官方文档，并与官方页面、本机安装源码及本仓库脚本交叉核对。用户报告的 Neovim 为 0.12.6；本文涉及的现代 LSP 接口以 Neovim 0.11+ 为基础。插件快捷键和 API 会随版本变化，实际安装版本的帮助与映射优先。

Context7 返回的一些配置示例仍包含旧插件名称或旧 API。本文采用当前 `mason-org/mason.nvim` 名称，并在 LazyVim 内通过 `opts.servers` 配置 LSP；不额外复制旧式 LSP setup 代码。

配套部署文档：[Windows C++ 环境脚本说明](nvim-cpp.md)。本文是一份教程，不会自动改变配置目录、安装插件或切换 clangd 来源。

## 阅读路线

- [1. 组件关系](#1-组件关系)
- [2. Neovim 基本操作](#2-neovim-基本操作)
- [3. Buffer、窗口、标签页与项目目录](#3-buffer窗口标签页与项目目录)
- [4. 配置、数据与环境变量](#4-配置数据与环境变量)
- [5. 文件结构与加载过程](#5-文件结构与加载过程)
- [6. 修改选项、快捷键和自动命令](#6-修改选项快捷键和自动命令)
- [7. 安装和配置插件](#7-安装和配置插件)
- [8. LazyExtras 与 Lua 预先导入](#8-lazyextras-与-lua-预先导入)
- [9. Mason clangd 与系统 LLVM](#9-mason-clangd-与系统-llvm)
- [10. CMake、编译数据库与 C++23](#10-cmake编译数据库与-c23)
- [11. 本仓库实际实现](#11-本仓库实际实现)
- [12. 日常工作流和多机复用](#12-日常工作流和多机复用)
- [13. 健康检查与排障](#13-健康检查与排障)
- [14. 学习顺序与资料](#14-学习顺序与资料)

Extras 与 clangd 的三个概念分别在 8.1（`:LazyExtras`）、8.2（Lua 预先导入）、9（Mason 与系统 LLVM）展开；它们涉及两类独立选择：如何启用扩展，以及从哪里取得 clangd。

## 1. 组件关系

### 1.1 各个名字分别是什么

| 名称 | 职责 | 使用者需要理解的内容 |
| --- | --- | --- |
| Neovim / `nvim` | 编辑器程序 | 模式、编辑命令、文件、窗口、内置 LSP 客户端 |
| Lua | 配置和插件使用的语言 | 表、函数、`require`、`vim.opt`、`vim.keymap` |
| lazy.nvim | Neovim 插件管理器 | 下载插件、按需加载、配置合并、插件锁文件 |
| LazyVim | 基于 lazy.nvim 的编辑器配置框架 | 默认快捷键、界面、补全、搜索、LSP 集成 |
| LazyVim starter | 用户配置的起步模板 | `init.lua`、`lua/config/`、`lua/plugins/` 的骨架 |
| LazyVim Extras | 按功能组合的插件和设置 | C/C++、CMake、调试等扩展 |
| Mason | 外部开发工具管理器 | 语言服务器、调试适配器、格式化器等程序的安装 |
| nvim-lspconfig | 常见语言服务器的配置定义 | 文件类型、启动命令、工程根目录等 |
| clangd | 独立的 C/C++ 语言服务器 | 解析真实编译参数，提供诊断、补全、跳转和重构 |
| Treesitter | 语法解析与相关插件 | 高亮、折叠等；语言解析器独立安装 |
| Blink | 补全界面与引擎 | 展示 LSP、片段等来源的补全候选 |
| conform.nvim | 格式化工具的调度插件 | 调用 clang-format、stylua 等程序 |
| nvim-dap / CodeLLDB | 调试客户端 / 调试适配器 | 断点、继续、单步、变量与调用栈 |
| CMake / Ninja / MSVC | 配置工程 / 执行构建 / 编译与链接 | 与编辑器集成，但有自己的安装和项目设置 |

例如，`nvim-lspconfig` 是 Lua 插件，`clangd.exe` 是该插件帮助启动的外部程序；安装前者不会在所有环境中自动提供后者。LazyVim 加上 Mason 的集成可以安排安装，但这是集成层的行为。

### 1.2 三个管理界面如何分工

| 命令 | 管理对象 | 示例 |
| --- | --- | --- |
| `:Lazy` | Neovim 插件代码 | blink.cmp、conform.nvim、nvim-dap |
| `:LazyExtras` | LazyVim 的扩展组合 | lang.clangd、lang.cmake、dap.core |
| `:Mason` | 外部程序 | clangd、CodeLLDB、Lua 语言服务器 |

Extras 会引入多条插件规格，还可能配置工具的自动安装清单。它不是新的编辑器，也不是某个单独的 EXE。

LazyVim 主体由 `LazyVim/LazyVim` 提供；个人配置从 `LazyVim/starter` 起步；`folke/lazy.nvim` 负责把这些插件加载进 Neovim。官方入口：[LazyVim 安装](https://www.lazyvim.org/installation)、[lazy.nvim](https://lazy.folke.io/)、[Mason](https://github.com/mason-org/mason.nvim)。

## 2. Neovim 基本操作

### 2.1 先认识模式

| 模式 | 进入方式 | 用途 | 返回普通模式 |
| --- | --- | --- | --- |
| 普通模式 Normal | 启动后或按 Esc | 移动、删除、复制、执行组合命令 | 已处于此模式 |
| 插入模式 Insert | `i`、`a`、`o` | 输入文字 | Esc |
| 可视模式 Visual | `v`；整行选择用 `V` | 选择一段或多行文本 | Esc |
| 命令行模式 | 普通模式下按 `:` | 保存、打开文件、运行插件命令 | 执行后返回；Esc 取消 |
| Terminal 模式 | 进入终端缓冲区并开始输入 | 操作终端里的程序 | `<C-\><C-n>` |

`<C-\><C-n>` 表示先按 Ctrl+反斜杠，再按 Ctrl+n。`<leader>` 是配置中的前导键，LazyVim 默认为空格；`<leader>ff` 就是依次按空格、f、f。`<CR>` 表示 Enter，`<Esc>` 表示 Esc。这些写法用于描述按键，不是要输入完整字符串。

### 2.2 第一批应掌握的编辑命令

以下是普通模式下的基础操作。LazyVim 可能覆盖个别默认映射，遇到差异时查映射和帮助。

| 按键 | 操作 |
| --- | --- |
| `h j k l` | 左、下、上、右 |
| `w` / `b` | 向后 / 向前移动一个单词 |
| `0` / `^` / `$` | 行首 / 第一个非空白字符 / 行尾 |
| `gg` / `G` | 文件开头 / 文件结尾 |
| `i` / `a` | 光标前 / 光标后输入 |
| `o` / `O` | 在下一行 / 上一行新建并输入 |
| `x` | 删除光标下字符 |
| `dd` | 删除当前行，内容进入寄存器 |
| `yy` / `p` | 复制当前行 / 粘贴 |
| `u` / Ctrl+r | 撤销 / 重做 |
| `/text` | 向后搜索 text |
| `n` / `N` | 下一处 / 上一处搜索结果 |
| `3j` / `5dd` | 向下三行 / 删除五行；数字是操作次数 |
| `ciw` | 修改光标所在单词并进入插入模式 |
| `.` | 重复上一次可重复的修改 |

删除与复制操作常用“操作符 + 范围”：`d` 删除、`y` 复制、`c` 修改；`w`、`$`、`iw` 等指定范围。无需一开始记住全部组合。

### 2.3 保存、退出、打开文件

```vim
:w
:q
:wq
:qa
:qa!
```

依次表示保存当前文件、关闭当前窗口、保存并关闭窗口、退出所有窗口、丢弃未保存内容并退出所有窗口。学习时先使用 `:w` 和 `:q`；带 `!` 的强制操作需要清楚其含义。

`:edit 路径` 打开文件。例如在项目根目录运行：

```vim
:edit src/main.cpp
```

终端里也可以先输入 `nvim 文件路径`。本仓库使用隔离应用名时，通过启动器传入项目路径，或先设置对应的 `NVIM_APPNAME`。

### 2.4 使用内置帮助

```vim
:help
:help user-manual
:help lua-guide
:help windows
:help stdpath()
:help vim.lsp
```

在帮助标签上按 Ctrl+] 跳到对应说明，Ctrl+t 返回。在当前窗口按 `:q` 关闭帮助窗口。需要练习基础操作时使用 `:Tutor`，以本机帮助中列出的教程为准。[Neovim 用户手册](https://github.com/neovim/neovim/blob/master/runtime/doc/usr_02.txt)。

## 3. Buffer、窗口、标签页与项目目录

### 3.1 Buffer 不等于窗口

| 概念 | 含义 | 示例 |
| --- | --- | --- |
| Buffer（缓冲区） | Neovim 内存里的文本或工具内容 | main.cpp、帮助、终端、诊断列表 |
| Window（窗口） | 展示一个 Buffer 的视口 | 左右分屏同时展示不同文件 |
| Tab page（标签页） | 一组窗口布局 | 一个标签页放源码，另一个放日志分屏 |

一个 Buffer 可以在两个窗口中显示；关闭窗口后，其 Buffer 也可能继续留在内存中。因此，Neovim 标签页不能直接等同于其他编辑器的文件标签。[窗口与缓冲区说明](https://github.com/neovim/neovim/blob/master/runtime/doc/windows.txt)。

### 3.2 常用原生命令

| 命令或按键 | 用途 |
| --- | --- |
| `:ls` | 列出缓冲区 |
| `:buffer 号码` | 切换到指定缓冲区 |
| `:bnext` / `:bprevious` | 下一个 / 上一个缓冲区 |
| `:bdelete` | 删除当前缓冲区，未保存修改通常会阻止操作 |
| `:split` / `:vsplit` | 上下 / 左右分屏 |
| Ctrl+w 然后 h/j/k/l | 切换到相邻窗口 |
| Ctrl+w 然后 = | 均分窗口 |
| `:tabnew` | 创建新的窗口布局标签页 |
| `:tabnext` / `:tabprevious` | 切换标签页 |
| `:terminal` | 创建终端缓冲区 |

LazyVim 对窗口和缓冲区还有快捷键；按空格查看 which-key，或在官方快捷键表中检索。[LazyVim 快捷键](https://www.lazyvim.org/keymaps)。

### 3.3 文件类型、工作目录、工程根目录

```vim
:set filetype?
:pwd
:lua print(vim.fn.getcwd())
:checkhealth vim.lsp
```

`filetype` 是 Neovim 对文件内容类型的分类，例如 `cpp`、`cmake`、`lua`，不只是文件扩展名。语言服务器和按文件类型加载的插件会使用它。

当前工作目录（cwd）用于解释相对路径；LSP 工程根目录由服务器配置中的标记等决定。打开深层目录的 main.cpp 时，clangd 可以识别外层工程根目录，而 cwd 仍是另外一个目录。

本仓库的 CMake 插件会把数据库复制到 `vim.fn.getcwd()`。所以执行工程配置命令时，cwd 应为该项目的 CMake 源码根目录。不能只根据状态栏显示的仓库名判断当前工作目录。

### 3.4 先记住少量 LazyVim 操作

| 按键 | 常见操作 |
| --- | --- |
| Space，然后暂停 | 显示可用快捷键提示 |
| `Space f f` | 查找文件 |
| `Space /` | 搜索项目文本 |
| `gd` | LSP 跳转定义 |
| `K` | LSP 查看符号说明 |
| `Space c r` | LSP 重命名 |
| `Space c a` | LSP Code Action |
| `Space c f` | 格式化 |
| `Space c d` | 查看当前行诊断 |
| `]d` / `[d` | 下一个 / 上一个诊断 |
| `Space c h` | clangd 扩展提供的头文件/源文件切换 |

这是与本次配置相关的操作集，不是保证所有版本完全相同的固定协议。LSP 操作需要服务器附加到文件；格式化需要对应程序可用。

### 3.5 当前 Blink 补全菜单怎么操作

本机 LazyVim 的 Blink 配置使用 enter 预设，并增加 Ctrl+y 的 select_and_accept 行为。插入模式下出现候选菜单后：

| 按键 | 当前配置中的操作 |
| --- | --- |
| Ctrl+n / Ctrl+p | 下一项 / 上一项 |
| Enter | 接受已选择候选；条件不满足时回到普通输入行为 |
| Ctrl+y | 选择并接受候选，减少“未选中时 Enter 换行”的困惑 |
| Ctrl+e | 取消补全，或回到原来的按键行为 |
| Ctrl+Space | 请求显示候选或切换补全文档显示 |
| Tab / Shift+Tab | 片段参数向前 / 向后跳转，取决于是否处于片段及当前配置 |

代码补全和冒号命令行补全可能使用不同预设，不应把命令行中的 Tab 行为直接套到 C++ 插入模式。终端或输入法也可能拦截 Ctrl+Space；这种情况先用自动候选菜单和 Ctrl+n/Ctrl+y。

可用 `:verbose imap <CR>` 和 `:verbose imap <C-y>` 检查当前映射。上述操作按本机当前源码核对，版本或用户覆盖变化后以实际映射为准。[Blink 按键预设源码](https://github.com/Saghen/blink.cmp/blob/main/lua/blink/cmp/keymap/presets.lua)。
## 4. 配置、数据与环境变量

### 4.1 Windows 默认路径与本仓库路径

| 内容 | 默认应用名 nvim | 本仓库默认应用名 nvim-cpp |
| --- | --- | --- |
| 用户配置 | `%LOCALAPPDATA%\nvim` | `%LOCALAPPDATA%\nvim-cpp` |
| 用户数据 | 通常 `%LOCALAPPDATA%\nvim-data` | 通常 `%LOCALAPPDATA%\nvim-cpp-data` |
| 插件 Git 仓库 | 数据目录下 `lazy/` | 数据目录下 `lazy/` |
| Mason 外部工具 | 数据目录下 `mason/` | 数据目录下 `mason/` |

这些是默认规则的常见展开。XDG 环境变量、Neovim 启动参数和插件选项可能改变实际目录；应在运行中的编辑器查询，而不是根据用户名猜测。

```vim
:lua print(vim.fn.stdpath("config"))
:lua print(vim.fn.stdpath("data"))
:lua print(vim.fn.stdpath("state"))
:lua print(vim.fn.stdpath("cache"))
:lua print(vim.env.NVIM_APPNAME)
```

`config` 保存用户意图；`data` 保存插件、工具等数据；`state` 常用于历史或日志等状态；`cache` 用于可重新生成的缓存。具体插件也可能把日志放在 data 中，例如本次 conform 和 LSP 报告显示的位置。四种职责不意味着每个插件严格使用同一种目录。[Neovim 标准目录规则](https://github.com/neovim/neovim/blob/master/runtime/doc/starting.txt)。

### 4.2 NVIM_APPNAME 不是复制操作

在启动 Neovim 前设置：

```powershell
$env:NVIM_APPNAME = 'nvim-cpp'
nvim
```

Neovim 会直接选择相应的标准目录。不是启动后再把 nvim-cpp 复制到 nvim，也不是插件目录改名脚本。

本仓库的启动器会自动设置应用名，退出后恢复当前进程原值。安装器仅把仓库配置复制到目标配置目录；第一次启动时才下载插件。

`$env:...` 影响当前 PowerShell 进程及其子进程，之后独立启动的终端通常不会保留该值。可用启动器、PowerShell Profile 中的短命令，或 Windows 用户环境变量选择日常入口。用户级持久变量会让普通 `nvim` 也选择该应用名；它不负责初始化 VS 编译环境。

### 4.3 XDG_CONFIG_HOME 只指定配置基础目录

```powershell
$env:XDG_CONFIG_HOME = 'D:\EditorConfig'
$env:NVIM_APPNAME = 'nvim-cpp'
```

此时配置目录为 `D:\EditorConfig\nvim-cpp`。不能因此推断数据目录也已经移动；数据目录由自己的规则决定。修改前后都可用 `stdpath` 查询。

在团队配置里保留变量和相对结构，避免提交 `C:\Users\某用户名\...` 这样的机器路径。特别是编译数据库，不应作为多机通用配置复制。

## 5. 文件结构与加载过程

### 5.1 官方 starter 风格的配置目录

以下目录在 Windows 上对应实际 `stdpath("config")`，不要求全部文件都存在：

```text
配置目录/
├── init.lua
├── lazy-lock.json
├── lazyvim.json
├── lua/
│   ├── config/
│   │   ├── lazy.lua
│   │   ├── options.lua
│   │   ├── keymaps.lua
│   │   └── autocmds.lua
│   ├── plugins/
│   │   ├── editor.lua
│   │   ├── cpp.lua
│   │   └── theme.lua
│   └── user/
│       └── helpers.lua
└── after/
    └── ftplugin/
        └── cpp.lua
```

`editor.lua`、`cpp.lua`、`theme.lua`、`user/helpers.lua` 是按职责取名的示例，不是 LazyVim 强制要求的文件名。[LazyVim 文件结构](https://www.lazyvim.org/configuration)。

### 5.2 每个文件的作用

| 文件 | 作用 | 适合写什么 |
| --- | --- | --- |
| `init.lua` | Neovim 用户配置入口 | 引导插件管理器；必须尽早执行的少量设置 |
| `lua/config/lazy.lua` | starter 的插件管理器引导文件 | lazy.nvim 安装、LazyVim 导入、明确的 Extras 导入、管理器选项 |
| `lua/config/options.lua` | LazyVim 加载的编辑器选项 | 行号、缩进、剪贴板、自动格式化偏好 |
| `lua/config/keymaps.lua` | LazyVim 加载的用户快捷键 | 使用 `vim.keymap.set` 添加或覆盖映射 |
| `lua/config/autocmds.lua` | LazyVim 加载的用户自动命令 | 文件类型等事件触发的行为 |
| `lua/plugins/*.lua` | lazy.nvim 用户插件规格 | 增加插件、覆盖 opts、声明加载条件、禁用插件 |
| `lua/user/helpers.lua` | 普通 Lua 模块 | 可复用函数；需要显式 require 才执行 |
| `after/ftplugin/cpp.lua` | C++ 文件类型加载后的设置 | `vim.opt_local` 设置 C++ 缓冲区选项 |
| `lazyvim.json` | LazyVim 框架维护的状态与 Extras 选择 | 随配置同步；保留框架维护的版本元数据 |
| `lazy-lock.json` | lazy.nvim 管理的插件 Git 版本 | 提交到配置仓库，用于多机 restore |

`lazyvim.json` 与 `lazy-lock.json` 的职责不同：前者可以记录“启用哪些扩展”，后者记录“插件使用哪些提交”。锁文件不会自行决定是否启用一个扩展。

### 5.3 一次启动大致发生什么

1. Neovim 按标准目录或 `-u` 参数选择用户入口。
2. 官方 starter 的 `init.lua` 执行 `require("config.lazy")`。
3. `lazy.lua` 引导 lazy.nvim，并声明 LazyVim、自定义插件等导入。
4. LazyVim 读取自己的默认设置和用户覆盖，导入 Extras；lazy.nvim 整理插件规格。
5. 缺失插件按安装策略下载，启动插件和后续事件触发的插件按各自条件加载。
6. 打开 cpp 文件后，语言支持插件配置 clangd，clangd 在合适的根目录启动并附加。

这是理解用的顺序图，不应据此手工 require 所有 config 文件。官方 starter 对 `config.lazy` 的入口 require 已经存在；用户的 options、keymaps、autocmds 则交给 LazyVim 在规定时机加载。[General Settings](https://www.lazyvim.org/configuration/general)。

### 5.4 Lua 模块如何对应文件

`require("user.helpers")` 会在 runtimepath 的 `lua/` 目录下查找 `user/helpers.lua` 或相应模块目录的 `init.lua`。它不是相对于 cwd 随便查找文件；`.` 表示模块层级，即使在 Windows 上也使用这个写法。

`require` 会缓存模块，重复 require 通常不会重新执行文件。修改配置后重启编辑器是较清晰的验证方式，不能把“反复 require”当成通用重载方法。[Neovim Lua 模块加载](https://github.com/neovim/neovim/blob/master/runtime/doc/lua-guide.txt)。

### 5.5 lua/plugins 与原生 plugin 目录不是一回事

原生 `plugin/`、`after/plugin/` 保存运行时脚本；lazy.nvim 接管插件加载后也会参与处理这些目录。`lua/plugins/` 则是 LazyVim 引导中的 `{ import = "plugins" }` 约定，文件应返回插件规格表。

普通 Neovim 并不会因为你建立了 `lua/plugins/` 就自动获得插件管理器。把一个插件 spec 放入 `plugin/` 也不等于登记了 lazy.nvim 插件。

使用 LazyVim 时优先沿用它的 `lua/config/`、`lua/plugins/` 结构。不要同时给同一批插件再建立另一套 packer、vim-plug 或原生 vim.pack 管理流程。

## 6. 修改选项、快捷键和自动命令

### 6.1 options.lua：编辑器选项

在部署目录的 `lua/config/options.lua` 中，例如：

```lua
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.scrolloff = 8
vim.opt.clipboard = "unnamedplus"
```

这些分别设置行号、相对行号、滚动边距和系统剪贴板。`vim.opt` 用于选项，`vim.g` 用于全局变量；插件也可能通过 `vim.g` 接受设置，两者不能随意互换。

LazyVim 默认支持保存时自动格式化。若希望先手动格式化，可以在这个文件设置：

```lua
vim.g.autoformat = false
```

之后仍可使用 Space c f 手动格式化。该变量是 LazyVim 的设置，不是 Neovim 所有发行配置都认识的通用选项。格式化器的选择放在对应插件 opts 中，项目格式规则放在 `.clang-format` 中。

### 6.2 keymaps.lua：添加自己的快捷键

下面示例用一个本仓库未占用的组合清除搜索高亮：

```lua
vim.keymap.set("n", "<leader>mH", "<cmd>nohlsearch<cr>", {
  desc = "Clear search highlight",
})
```

`n` 表示普通模式；`<cmd>...<cr>` 执行命令；`desc` 帮助 which-key 和映射检查显示用途。这个例子中 H 是大写字母，需要 Shift+h。

改快捷键前可查询已有定义：

```vim
:verbose nmap <leader>mH
:verbose nmap <leader>cf
```

`verbose` 通常还能指出映射最后定义的位置。遇到键盘终端兼容问题，先选简单字母组合，不必立即修改整套键位。

### 6.3 autocmds.lua：事件触发的行为

例如，让 C++ 缓冲区显示第 100 列参考线：

```lua
local group = vim.api.nvim_create_augroup("UserCppGuide", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "cpp",
  callback = function()
    vim.opt_local.colorcolumn = "100"
  end,
})
```

group 使重复加载时可以清除该组旧定义；FileType 表示文件类型确定时触发；`vim.opt_local` 针对当前缓冲区或窗口的局部选项。它不会改变项目编译参数。

也可以把下面这一行放在 `after/ftplugin/cpp.lua` 中完成相同目的：

```lua
vim.opt_local.colorcolumn = "100"
```

这是两种可选组织方法，选一种即可。LazyVim 已经提供了很多自动行为，增加新自动命令前先检查是否已有同样功能。

### 6.4 如何找到并打开自己的配置

```vim
:lua print(vim.fn.stdpath("config"))
:lua vim.cmd.edit(vim.fn.stdpath("config") .. "/lua/config/options.lua")
```

第二条使用实际配置目录，不依赖你是默认 nvim 还是 nvim-cpp，也不要求硬编码 Windows 用户名。确认保存位置是部署目录，而不是下载的 LazyVim 插件源代码目录。

如果修改的是本仓库模板，随后还需要运行安装器的 `-Update` 才会复制到部署目录。直接修改部署目录则立即成为本机修改；日后更新共享模板时，对受管理同名文件仍可能覆盖，因此团队改动应回写到仓库模板。

## 7. 安装和配置插件

### 7.1 官方页面的 Options 与 Full Spec

LazyVim 插件或 Extras 页面展示的 Options 和 Full Spec，是框架已经提供的默认设置/实现，方便查阅。并不是要求把整页代码复制到个人目录。

常见操作是：先启用需要的官方扩展，再在 `lua/plugins/` 中覆盖少量选项。修改下载目录里的源码会在插件更新时丢失，也难以同步到其他机器。[LazyVim 插件配置](https://www.lazyvim.org/configuration/plugins)。

### 7.2 插件文件为什么需要 return

`lua/plugins/` 中一个常见文件形态是：

```lua
return {
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "catppuccin" },
  },
}
```

外层表是插件规格列表，内层表是一条规格。GitHub 的 `组织/仓库` 字符串定位插件；`opts` 是交给插件的配置。

示例选择 catppuccin 主题，前提是该主题插件已经由配置提供。用户截图中的 catppuccin 正是已声明但尚未加载的主题。重复写同一插件的规格用于合并或覆盖，不意味着安装第二份该插件。

这里的 `theme.lua` 只是一个文件名；可命名为 `appearance.lua`。关键是放在被导入的 plugins 目录，并返回有效规格。

### 7.3 安装一个新插件的完整例子

以下是学习“声明 → 下载 → 加载 → 配置”的可选例子。不是 C++ 工作流的必需依赖，本次文档生成也不会安装它。

在部署目录创建 `lua/plugins/zen-mode.lua`：

```lua
return {
  {
    "folke/zen-mode.nvim",
    main = "zen-mode",
    cmd = "ZenMode",
    opts = { window = { width = 100 } },
  },
}
```

重启 Neovim，打开 `:Lazy` 检查新插件是否已安装；需要时执行 `:Lazy install` 安装缺失插件。随后运行：

```vim
:ZenMode
```

`cmd = "ZenMode"` 声明命令触发加载；`main` 明确 setup 模块；`opts` 指定窗口宽度。再次运行命令可退出对应模式。具体插件功能依据其 [官方说明](https://github.com/folke/zen-mode.nvim)。

目录存在、Lua 语法正确、下载成功、插件已加载、功能运行正常，是五个不同的检查点。

### 7.4 常用 spec 字段

| 字段 | 含义 | 使用时机 |
| --- | --- | --- |
| `[1]` | GitHub 仓库名等插件来源 | 声明新插件或覆盖同名插件 |
| `opts` | setup 选项，或修改已有 opts 的函数 | 优先用于一般插件配置 |
| `main` | 自动 setup 的模块名 | 自动推断不明确时 |
| `config` | 加载插件时执行的配置函数 | 插件需要特殊初始化时 |
| `init` | 启动阶段执行的函数 | 设置插件读取的早期 vim.g 等变量 |
| `dependencies` | 依赖的其他 Neovim 插件 | 声明插件依赖关系 |
| `event` | 如 InsertEnter、VeryLazy | 按事件加载 |
| `ft` | 如 cpp、lua | 按文件类型加载 |
| `cmd` | 插件命令 | 首次调用命令时加载 |
| `keys` | 快捷键及描述 | 首次使用快捷键时加载 |
| `enabled` | 是否纳入启用规格 | 禁用某个插件 |
| `build` | 安装/更新等阶段的构建操作 | 按该插件的正式安装要求填写 |
| `branch` / `tag` / `commit` | 选择代码版本 | 需要特定版本时 |
| `priority` | 启动插件之间的加载优先级 | 如需要提前加载主题 |

这些是概念和常见用法，完整类型见 [lazy.nvim Plugin Spec](https://lazy.folke.io/spec)。`dependencies` 不会替代操作系统的软件包管理器：需要 cmake.exe 的插件仍需要可执行文件可用。

### 7.5 opts 与 config 的区别

`opts = {...}` 通常让管理器或继承的配置逻辑调用插件 setup。修改 LazyVim 已经配置的插件时，优先使用 opts，以保留原有集成。

`config = function(_, opts) ... end` 自己决定如何调用 setup 或执行其他逻辑；覆盖一个已有的复杂 config 可能失去 LazyVim 原本的初始化步骤。

`init` 在启动阶段执行，即使插件本来准备延迟加载。若在 init 中随意 require 插件模块，可能提前触发该插件加载，使懒加载失去预期效果。

### 7.6 表覆盖与函数修改

字典形式的 opts 通常与已有设置合并；列表字段可能替换，而不是自动追加。部分 LazyVim 插件显式声明了列表扩展规则，不能据此认为所有列表都相同。

修改已配置插件的特定值，例如在 `lua/plugins/appearance.lua`：

```lua
return {
  {
    "folke/tokyonight.nvim",
    opts = function(_, opts)
      opts.transparent = false
    end,
  },
}
```

这会在已有 opts 上修改一个值。新建整个返回表则可能替换更多设置。对列表追加时应确认字段存在且是列表，再使用 `table.insert` 或 `vim.list_extend`；具体字段由该插件文档决定。[LazyVim 覆盖示例](https://www.lazyvim.org/configuration/examples)。

### 7.7 禁用插件、卸载文件和关闭工具的区别

在一个插件规格文件中，例如：

```lua
return {
  { "folke/flash.nvim", enabled = false },
}
```

这会禁用 flash 插件规格。磁盘上的旧插件目录可能暂时保留；`:Lazy clean` 用于清理不再需要的插件目录。执行前查看清理列表。

关闭某个插件功能，应该使用其功能选项；禁用整插件用 enabled；卸载 Mason 中的外部程序则由 Mason 管理。这三种动作的影响范围不同。

### 7.8 安装与加载：解释 :Lazy 界面

`:Lazy` 列表中的 Total 是管理的插件数量；Loaded 是本次会话已加载的插件；Not Loaded 是尚未触发加载的插件。Not Loaded 不等于下载失败。

右侧的 `cpp`、`BufReadPre`、命令或快捷键可以是触发条件；Loaded 一栏右侧通常说明已经因何事件、依赖或 require 被加载。毫秒数是加载耗时，不是网络下载进度。

开启一个扩展，不会要求其所有插件立即运行；已经下载的语言插件通常在打开对应文件后加载。[懒加载机制](https://lazy.folke.io/spec/lazy_loading)。

### 7.9 :Lazy 管理命令

| 命令 | 作用 | 是否改变版本或磁盘内容 |
| --- | --- | --- |
| `:Lazy` | 打开管理界面 | 本身不是更新命令 |
| `:Lazy install` | 安装缺失插件 | 下载插件 |
| `:Lazy check` | 检查可用更新 | 可执行 Git fetch |
| `:Lazy update` | 更新插件 | 更新代码和锁文件 |
| `:Lazy sync` | install、clean、update 的组合 | 安装、清理并更新 |
| `:Lazy restore` | 按锁文件恢复插件版本 | 调整插件代码版本 |
| `:Lazy clean` | 清理不再需要的插件 | 删除所选插件目录 |
| `:Lazy profile` | 查看性能分析 | 用于观察加载情况 |
| `:LazyHealth` | LazyVim 提供的综合健康检查入口 | 会加载更多插件用于检查 |

在 :Lazy 界面按 Enter 展开插件详情，按 `?` 查看当前界面帮助。多机复现版本使用 restore；sync 会更新版本，不是单纯让所有插件进入 Loaded。[lazy.nvim 使用说明](https://lazy.folke.io/usage)。

## 8. LazyExtras 与 Lua 预先导入

这一章详细解释两个启用 C++ 扩展的入口。两者引入的可以是同一个官方扩展，区别在于谁记录和管理“是否启用”。

### 8.1 第一项：使用 :LazyExtras

官方推荐的便捷入口是：

```vim
:LazyExtras
```

在列表中搜索或找到 `lang.clangd`、`lang.cmake`，按当前界面提示切换。核对的本机版本使用 `x` 切换，并要求重启 LazyVim 应用变更；以实际界面帮助为准。

操作不是让你手工配置所有 LSP、Treesitter、格式化和调试依赖。框架根据扩展定义，组合相关插件规格与选项。[官方 Extras 说明](https://www.lazyvim.org/extras)。

#### 选择保存在哪里

本机源码显示，用户选择会写入实际配置目录的 `lazyvim.json` 的 extras 列表。以下仅是理解用的字段示例，不是要求覆盖整个文件：

```json
{
  "extras": [
    "lazyvim.plugins.extras.lang.clangd",
    "lazyvim.plugins.extras.lang.cmake"
  ]
}
```

真实文件还可能包含 version、install_version、news 等框架元数据，交给 LazyVim 维护。其他机器要复用界面选择，需要同步这个文件；仅复制 `lua/plugins/cpp.lua` 或 lazy-lock.json 不一定复现 Extras 选择。

#### 打开 C++ 扩展后获得什么

lang.clangd 的定义会配置 C++ 解析器、clangd 扩展、LSP 等。启用了调试基础后，其可选 DAP 规格还会提供 CodeLLDB 集成。lang.cmake 在当前官方定义中也包含 cmake-tools.nvim 的集成。

扩展不负责把项目改成 C++23，不替你安装 MSVC/SDK，也不自动猜出所有项目宏。它仍需要真实编译参数。

适合此入口的情况：希望跟随官网教程，直观选择语言能力，并用 lazyvim.json 管理配置。无需为相同扩展再复制整页 Full Spec。

### 8.2 第二项：在 Lua 中预先导入

本仓库的 `lua/config/lazy.lua` 使用如下排列：

```lua
local specs = {
  { "LazyVim/LazyVim", import = "lazyvim.plugins" },
  { import = "lazyvim.plugins.extras.lang.clangd" },
  { import = "lazyvim.plugins.extras.lang.cmake" },
  { import = "lazyvim.plugins.extras.dap.core" },
  { import = "plugins" },
}
```

这段 specs 传给已经引导好的 `require("lazy").setup`。它不是完整独立的 init.lua；不要绕过现有引导重复调用 setup。

`import` 会收集模块提供的插件规格，不等于立即加载全部插件。顺序应保持 LazyVim 主体在前、Extras 随后、用户 plugins 最后，让用户覆盖建立在框架和扩展基础上。本机 LazyVim 还会检查导入顺序。

选择由 Lua 代码记录，配置仓库的评审与同步就能看到启用了哪些能力。团队固定基础扩展时比较直观；个人使用者要关闭某个导入则需要改代码并重启。

#### 为什么界面可能不让关闭

本机 LazyExtras 源码对已启用、但不是由其 JSON 列表管理的扩展，会提示无法在界面开关，需要从配置里移除。

这不会说明扩展损坏。界面不负责删除你写在 Lua 文件中的 import。为了清楚管理，同一扩展应选择一个主要的启用入口；不要依赖同时修改 JSON 与 Lua 来互相抵消。

当前仓库预先导入了 C++、CMake 和 DAP，所以使用者不需要再在 :LazyExtras 中重复添加它们。

### 8.3 两种启用方式对比

| 项目 | :LazyExtras | Lua 显式 import |
| --- | --- | --- |
| 操作位置 | 编辑器界面 | 用户 Lua 文件 |
| 主要持久化文件 | lazyvim.json | 包含 import 的 Lua 文件 |
| 可读性 | 适合浏览和尝试扩展 | 适合代码评审与固定团队方案 |
| 关闭方法 | 通过界面切换其管理的项目 | 修改对应 import 并重启 |
| 扩展功能来源 | 官方扩展定义 | 同一个官方扩展定义 |
| 插件实际加载 | 仍遵循事件等条件 | 仍遵循事件等条件 |

### 8.4 这与覆盖插件 opts 并不冲突

无论扩展从哪个入口启用，都可以在 `lua/plugins/cpp.lua` 中覆盖少量插件选项。三个层次是：

```text
是否启用扩展：LazyExtras 的记录，或者 Lua import
扩展默认行为：LazyVim 官方扩展规格
用户差异：lua/plugins/*.lua 的 opts、keys 等覆盖
```

例如，本仓库启用官方 clangd 扩展后，再覆盖 clangd 的可执行文件来源和实时 clang-tidy 开关。以后若把扩展启用入口改为 LazyExtras，这些确有需要的 opts 覆盖仍可以保留。

## 9. Mason clangd 与系统 LLVM

### 9.1 第三项：选择 clangd 的来源

这项选择独立于上一章的扩展启用方式。你可以用 LazyExtras 启用扩展并使用系统 LLVM，也可以用 Lua import 启用扩展并交给 Mason 安装 clangd。

| 扩展启用方式 | Mason clangd | 系统 clangd |
| --- | --- | --- |
| :LazyExtras | 可以 | 可以，增加相应覆盖 |
| Lua import | 可以 | 可以；本仓库采用这一组合 |

lang.clangd 负责配置语言能力；Mason 或系统安装方式负责提供可执行文件。改变工具来源，不等于换一个 C++ 语言扩展。

### 9.2 默认通过 Mason 管理的含义

LazyVim 的 LSP 集成会查看启用的服务器，以及 Mason 的可用映射。对于支持的服务器，默认安排 Mason 安装，并通过相应集成启用。clangd 属于这种常见情况。

从本机当前 LazyVim 源码可以看到：只有服务器配置没有设置 `mason=false`，并且存在映射时，才选择该安装流程。Mason 的默认安装根目录为：

```text
stdpath("data")/mason/
├── bin/                 启动程序的链接或包装入口
└── packages/            安装的软件包内容
```

Windows 中 bin 下可能是 CMD 等包装文件，不一定每个工具都是直接的 EXE。Mason 默认把 bin 放到 Neovim 进程 PATH 的前面；这不是把所有系统终端的持久 PATH 都改成 Mason 路径。[Mason 安装与 PATH](https://github.com/mason-org/mason.nvim)。

通常先启用 C++ 扩展，再用 `:Mason` 观察 clangd 安装状态。安装失败时查看详情和 `:MasonLog`。包名和 LSP 配置名有时不同，例如 `lua-language-server` 对应 `lua_ls`、`neocmakelsp` 对应 `neocmake`。

### 9.3 Mason 提供什么、不提供什么

Mason 可以安装 clangd，但这不意味着已安装完整 LLVM 编译工具链、MSVC、Windows SDK、CMake 和 Ninja。

clang-format 也是独立工具；不能仅因 clangd 已安装就推断独立 clang-format 命令也已存在。实际格式化由哪个工具执行，以 `:ConformInfo` 等检查结果为准。

在纯 Lua 插件中使用 Python 工具，与 Neovim 的 Python provider 也是不同关系。provider 用于调用用对应语言编写的远程插件；Mason 使用 Python/pip 安装某些工具，不等于要求所有人安装 pynvim。

### 9.4 使用系统 LLVM 的含义

本仓库使用 Scoop 或已有系统安装提供的 LLVM，其可用性通过命令检查。所需工具包括：

```text
clangd.exe        C/C++ 语言服务器
clang-format.exe 格式化工具
clang-tidy.exe   静态检查工具
clang-cl.exe     使用 MSVC 风格参数的 Clang 编译器
```

启动 Neovim 时，`init.lua` 会在 Mason 修改 PATH 之前查询 clangd 和 clang-format 的实际路径。随后用户插件配置明确使用这些路径，并让 clangd 退出 Mason 自动安装流程。

概念示例，在一个用户插件规格中选择具体 clangd：

```lua
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          mason = false,
          cmd = { "D:/tools/llvm/bin/clangd.exe", "--background-index" },
        },
      },
    },
  },
}
```

路径必须替换为本机实际可信路径。这个例子只展示来源选择；本仓库的 `cpp.lua` 已经提供相同职责，不要额外复制第二个规格来无意覆盖现有 cmd。

### 9.5 mason=false、PATH 与 cmd 是三件事

| 设置 | 实际作用 | 不应推断的事情 |
| --- | --- | --- |
| `servers.clangd.mason=false` | 告诉 LazyVim 不走该服务器的 Mason 自动安装选择 | 不会卸载已经存在的 Mason clangd |
| Mason `PATH="append"` | 把 Mason bin 放到本次 Neovim PATH 后面 | 不能保证所有同名命令都是系统版本 |
| `clangd.cmd[1]` 为绝对路径 | 明确启动哪份 clangd | 不会自动验证该程序支持项目全部语法 |

`mason` 是 LazyVim 扩展的服务器配置选项，不是 clangd 的协议参数，也不是“禁用整个 Mason”的开关。

如果 cmd 是简单的 `"clangd"`，仍然会按启动时有效 PATH 查找。系统 clangd 缺失、但旧 Mason clangd 还在 PATH 中时，仍可能找到后者。确认来源应看 :checkhealth vim.lsp 中实际 Active Client 的 Command，不能只看 Mason 列表。

若安装了多套 LLVM，本仓库可用部署目录的 `local.lua` 指定路径。机器路径保留在本机，不写入共享项目的 `.clangd`。

### 9.6 两种来源的取舍

| 项目 | Mason clangd | 系统 LLVM |
| --- | --- | --- |
| 上手 | 跟随 LazyVim 语言服务管理较直观 | 先准备系统工具和 PATH |
| 命令行与编辑器统一 | 需要确认系统终端是否也使用同一版本 | 容易与命令行工具统一，仍需检查 PATH |
| 版本管理 | 随 Mason 包安装策略维护 | 随 Scoop、安装包或公司镜像维护 |
| clang-format/clang-tidy/clang-cl | 不能由“已装 clangd”直接推断 | 完整 LLVM 安装可提供，按实际命令验证 |
| VS/SDK | 仍需单独准备 | 仍需单独准备 |
| 编译数据库 | 仍需真实数据库 | 同样需要真实数据库 |

当前已有系统 LLVM，并采用 MSVC/clang-cl 工作流，所以本仓库选择系统 LLVM。这个选择不是 LazyVim 必需规定，也不是 Mason clangd 无法用于 Windows C++。

### 9.7 如果以后切换来源

切换前记录实际 clangd 版本、启动命令、格式化器命令和项目数据库。

从系统改成 Mason，应一并检查当前 `cpp.lua` 的 `mason=false` 和绝对 cmd 覆盖。仅把 false 改成 true，却保留系统绝对路径，仍可能安装了 Mason clangd、实际运行系统 clangd。

从 Mason 改成系统，应准备可执行文件、明确 cmd 并关闭对应的自动安装安排。旧 Mason 包是否卸载属于另一个决定，不需要通过删除整个数据目录实现。

更改后重启编辑器，并在真正的 cpp 缓冲区验证 Active Client 的 Command 和功能。不要在 LazyVim 的 opts 集成之外再为同一服务器重复手写一套启动逻辑。[官方 clangd 扩展默认设置](https://www.lazyvim.org/extras/lang/clangd)。

## 10. CMake、编译数据库与 C++23

### 10.1 C++23 不由主题或 Extras 决定

启用 lang.clangd 后，补全和导航的框架已经配置；项目到底按哪个标准解析，来自该翻译单元的编译参数。

示例目标在 CMake 中声明：

```cmake
target_compile_features(nvim_cpp_smoke PRIVATE cxx_std_23)
```

CMake 根据具体编译器选择可用的标准选项。对某些 MSVC 版本可能生成 `/std:c++latest` 之类选项，不能要求所有编译器都产生字面相同的 `-std=c++23`。

这是至少采用该标准级别的构建要求，不保证所用编译器和标准库已实现所有 C++23 特性；本仓库通过 std::expected 示例验证了一部分能力。

### 10.2 为什么需要 compile_commands.json

clangd 不会自己运行整个 CMake 工程。数据库为源文件记录编译工作目录、编译器、标准、宏和头文件路径，帮助它与真实构建采用一致的解析参数。[clangd 工程设置](https://clangd.llvm.org/installation#project-setup)。

Ninja/Makefile 类生成器支持 `CMAKE_EXPORT_COMPILE_COMMANDS`；Visual Studio 生成器不直接支持这个导出开关。[CMake 官方说明](https://cmake.org/cmake/help/latest/variable/CMAKE_EXPORT_COMPILE_COMMANDS.html)。

多配置时选择当前活动数据库，避免混合 Debug/Release 或不同工具链下同一文件的相互冲突命令。CMake 的 Unity Build 也不适合作为独立源文件数据库的通用表达，因此示例的工具配置关闭了它。

### 10.3 五类项目文件的职责

| 文件 | 职责 |
| --- | --- |
| `CMakeLists.txt` / Presets / 工具链文件 | 定义如何真正配置和构建项目 |
| `compile_commands.json` | 构建系统生成的逐文件解析参数 |
| `.clangd` | 必要的语言服务器行为调整和数据库发现策略 |
| `.clang-format` | 代码排版规则 |
| `.clang-tidy` | 静态检查规则 |

不用把构建系统已有的所有标准、宏和 include 路径再写一遍到 `.clangd`。本仓库也没有自动给所有项目生成全局 `.clangd`。

### 10.4 Windows 开发环境为什么仍需准备

MSVC/Ninja 构建需要合适的编译器、链接器、Windows SDK 和标准库环境。可以从 VS Developer PowerShell 启动，也可以用本仓库启动器初始化当前进程环境。

普通 `nvim`、设置 NVIM_APPNAME 和安装 clangd 都不能替代 VS 环境初始化。clang-cl 使用 MSVC 风格的 ABI/工具链时，同样通常需要相应的 MSVC/SDK 环境。

### 10.5 通过命令行验收本仓库示例

完整命令统一维护在 [部署说明：验收一个 C++23 工程](nvim-cpp.md#验收一个-c23-工程)，包括 VS 环境初始化、MSVC / clang-cl 构建、CTest、数据库同步和单文件 clangd 检查。

只有 configure 成功后才同步数据库。不同配置使用独立 build 子目录；`-EnvironmentOnly` 必须在当前 PowerShell 会话调用才能影响后续 CMake。

### 10.6 在 Neovim 内操作 CMake

先确保 cwd 是项目的 CMake 源码根目录，然后：

```vim
:CMakeSelectConfigurePreset
:CMakeGenerate
:CMakeSelectBuildPreset
:CMakeSelectBuildTarget
:CMakeBuild
:CMakeSelectLaunchTarget
:CMakeRun
```

这是本仓库 cmake-tools 配置所用的一套入口。选择 Preset 与实际 configure 是不同动作；数据库来自成功的 configure。项目测试可以使用 :CMakeRunTest。

本仓库为常用命令定义 Space m p/g/b/t/r/d/s。官方扩展默认键位可能不同，不应把这些定制当成全部官网的固定键位。

### 10.7 已连接 clangd 仍可能解析错误

本次用户报告出现过：clangd 已附加、根目录正确，但日志显示找不到数据库，并使用 fallback 和 C++14 标准库索引。原因是数据库位于 `build/msvc-debug`，根目录未同步，而当前启动参数没有指向那个深层构建目录。

需要观察三层证据：

1. 服务器已启动并附加到文件。
2. 日志加载了预期数据库，并为该文件选择真实编译命令。
3. 标准库和项目头文件解析正确，补全、跳转、构建结果符合预期。

:checkhealth vim.lsp 中的 Enabled Configurations 只表示配置已注册；Active Clients 表示正在运行。两者都不能单独证明数据库正确。

可在 VS 环境终端检查指定文件：

```powershell
clangd --check=src/main.cpp `
    --compile-commands-dir=build/msvc-debug --log=verbose
```

这个检查显式传入构建目录。它通过后，还需确认编辑器也能发现同一个目录；不能因为命令行显式 check 成功，就认为未同步根数据库的编辑器已自动修复。

### 10.8 数据库发现与刷新策略

本仓库默认把当前活动数据库复制到项目根目录。clangd 通常会从源文件目录向祖先目录寻找数据库，也有特定的 build 目录查找规则；不能指望任意深度的 build 子目录都自动被发现。

团队还可以选择用 `.clangd` 的 `CompileFlags.CompilationDatabase` 或启动参数指定固定目录，但应与复制策略保持一致，避免选中两套不同配置。[编译命令的工作方式](https://clangd.llvm.org/design/compile-commands)。

共享配置中的机器路径、无法解析的数据库、生成头文件缺失和不兼容编译选项，都可能产生误报。先修参数，再判断 unused include 等诊断；不要直接删除 std::expected 所需头文件或全局抑制全部错误。

## 11. 本仓库实际实现

### 11.1 共享模板与运行目录

```text
本仓库 scripts/nvim/config/
        │ Install-NvimCpp.ps1 复制受管理文件
        ▼
本机 stdpath("config")，默认 nvim-cpp/
        │ Start-NvimCpp.ps1 选择应用名并准备 VS 环境
        ▼
Neovim 运行配置，lazy.nvim/Mason 使用相应数据目录
```

修改仓库模板和修改运行目录，是两个不同操作。模板用来多机同步；运行目录是编辑器真正读取的位置。

### 11.2 配置与示例文件

| 仓库文件 | 当前职责 |
| --- | --- |
| `config/init.lua` | 读取本机 local.lua，提前确定 LLVM 路径，再 require config.lazy |
| `config/lua/config/lazy.lua` | 引导 lazy.nvim，导入 LazyVim/C++/CMake/DAP 和用户插件 |
| `config/lua/config/options.lua` | 行号、剪贴板、撤销等基础选项 |
| `config/lua/config/local.example.lua` | 本机工具路径与 clang-tidy/并发参数的示例 |
| `config/lua/plugins/cpp.lua` | 系统 clangd、conform、Mason PATH、CMake 插件选项及快捷键覆盖 |
| `examples/cpp23/` | Presets、std::expected 示例和格式/静态检查配置 |
| `tests/` | 配置部署/数据库的隔离回归，以及使用替代模块的 Lua 语法和选项检查 |

脚本职责与部署操作统一见 [部署说明：文件入口](nvim-cpp.md#文件入口)。keymaps.lua 和 autocmds.lua 当前不在共享模板里；没有这两个用户覆盖文件，不影响 LazyVim 提供默认行为。

### 11.3 local.lua 是本仓库约定

`local.lua` 并非所有 LazyVim starter 都自动读取的标准文件。本仓库的 init.lua 明确使用 dofile 读取它，并要求返回一个表。

示例文件需要在部署目录中复制成 local.lua 才会生效。可以设置 clangd/clang-format 路径、实时 clang-tidy 与额外 clangd 参数。默认不启用实时 clang-tidy；构建宏和标准仍来自数据库。

共享模板中同名受管理文件的修改，会由 `-Update` 覆盖；部署目录的 local.lua 等附加文件会保留。新增文件不会自动使其成为通用配置：必须明确由谁加载。

### 11.4 安装器的行为边界

安装器比较模板文件哈希，内容相同不重写；不同且目标配置已存在时，需用 -Update 明确更新。更新会备份配置目录，再覆盖变更文件；不会删除旧附加插件文件。

-InstallTools 按可执行命令是否存在决定是否调用已有 Scoop，不自动升级现有版本。它不安装 VS、SDK 或字体，也不在部署阶段下载 Neovim 插件。

-LockFile 校验 JSON 对象和每条完整 Git 提交值。只替换锁文件时也会备份；如果 Lua 模板同时发生变化，仍需要 -Update。现有插件需要在启动后 restore 才会回到所提供版本。

备份的是配置目录，不包含全部数据、系统工具或构建产物，也不是完整离线 Bundle。

### 11.5 当前配置与官网的具体差异

| 项目 | 官方入门常见流程 | 本仓库选择 |
| --- | --- | --- |
| 用户配置起点 | 克隆 starter | 仓库保存自己的引导模板 |
| 应用名 | nvim | nvim-cpp，以便隔离试用 |
| Extras 选择 | LazyExtras 界面 | Lua 固定导入 C++/CMake/DAP |
| clangd 来源 | 默认 Mason 集成 | 系统 LLVM，并显式关闭对应安装选择 |
| 日常启动 | nvim | 启动器同时初始化 VS |
| 插件更新检查 | starter 默认定期检查 | 关闭后台检查，按需手动操作 |
| 实时 clang-tidy | 官方 clangd extra 默认开启 | 当前默认关闭，解析稳定后按需启用 |

这些是部署与工程取舍，不是 LazyVim 要求每个初学者都必须完成的步骤。后续若选择更贴近官网，可以保留标准 starter 结构，用 LazyExtras 记录扩展，再只保留必要的 Windows 工具链覆盖。本文不自动执行这种迁移。

## 12. 日常工作流和多机复用

### 12.1 每天先完成一个小闭环

1. 在已有 VS 环境中进入工程，或使用本仓库启动器。
2. 使用文件查找打开源文件；确认 filetype 为 cpp。
3. 确认 clangd Active Client 附加；测试 K 和 gd。
4. 编辑、保存；需要时使用 Space c f 格式化。
5. 按项目 Preset 构建目标，查看编译输出。
6. 使用项目测试入口验证改动。

遇到补全异常时，先查 LSP 和数据库；遇到格式化异常时，查 ConformInfo 和 `.clang-format`；遇到构建失败时，查 CMake/编译器输出。这些子系统可以分别诊断。

### 12.2 使用一个短启动命令

PowerShell Profile 可以加入下面的函数，路径按实际仓库位置修改：

```powershell
function ncpp {
    param([string]$ProjectPath = '.')
    & 'D:\code\pwsh\common_records\scripts\nvim\Start-NvimCpp.ps1' `
        -ProjectPath $ProjectPath
}
```

加载了该 Profile 的终端中可以运行 `ncpp` 或 `ncpp D:\Projects\MyProject`。它只是简化入口，仍由启动器选择应用名和 VS 环境。实际哪个 Profile 被加载，以该终端的 `$PROFILE` 为准；Windows PowerShell 与 PowerShell 7 的 Profile 位置可能不同。

本仓库运行脚本要求 PowerShell 7。若执行策略阻止 Profile，不应只为消除健康检查文字而盲目更改系统全局策略；先明确哪个宿主需要运行哪份脚本。

### 12.3 标准路径和隔离路径都能使用

安装和启动脚本都传入 `-AppName nvim` 时使用标准应用名；都使用默认值时选择 nvim-cpp。两端应一致。

迁移到标准目录前，确认那里是否已有配置，并先备份。路径迁移、Extras 启用入口改变、clangd 来源切换，是三个不同变量，分开验证能减少排障成本。

### 12.4 多机应该共享哪些文件

| 内容 | 共享方式 |
| --- | --- |
| 用户 Lua 配置 | 同步受控配置仓库 |
| lazyvim.json | 使用 LazyExtras 时同步其选择，保留框架元数据 |
| lazy-lock.json | 同步验证过的插件版本记录 |
| 项目 Presets、格式和检查规则 | 跟随项目仓库 |
| VS/SDK/LLVM 等版本要求 | 记录团队基线并分别安装/验收 |
| local.lua 里的个人路径 | 每台机器按需填写 |
| 编译数据库、build、PDB | 每台机器本地生成 |
| 插件/Mason/解析器缓存 | 不当作通用配置；离线复制需另行验证平台和路径 |

懒加载触发条件由共享配置提供，但某次会话中的 Loaded 数量不需要在各机一致，因为打开的文件和执行的操作不同。

### 12.5 正确使用锁文件

第一台机器的插件功能验收通过后，把 lazy-lock.json 保存到团队配置仓库。其他机器导入后使用 :Lazy restore。

要升级团队插件版本，先在一台机器上 update 和验收，再共享新锁文件。lazy-lock.json 固定插件 Git 提交，不固定所有 Mason 二进制、Treesitter 解析器、VS 工具集和 SDK。[锁文件说明](https://lazy.folke.io/usage/lockfile)。

当前安装器不会自动把部署目录新生成的 lazy-lock.json 回写仓库。需要明确导出/同步；具体做法见配套脚本文档。同步 Lua 但遗漏 Extras 选择或版本记录，会造成机器之间的差异。

### 12.6 调试最后再验收

启用 dap.core 并准备 CodeLLDB 后，选择 Debug 可执行文件，验证断点、变量和调用栈。Mason 显示 Installed、DAP 健康检查显示 executable，都只证明对应阶段完成。

Windows PDB 调试信息在 LLDB 中仍需按目标验证。涉及复杂宿主进程、CAD/ZRX DLL、符号加载等场景，可继续使用 Visual Studio 原生调试器；编辑器、构建和调试工具可以分别选择。[CodeLLDB Windows 说明](https://github.com/vadimcn/codelldb/wiki/Windows)。

## 13. 健康检查与排障

### 13.1 哪条命令回答哪类问题

| 命令 | 用途 |
| --- | --- |
| `:Lazy` | 插件声明、安装与加载状态 |
| `:LazyExtras` | 当前扩展和启用入口 |
| `:Mason` / `:MasonLog` | 外部工具安装状态和安装日志 |
| `:LazyHealth` | LazyVim 综合检查，可能包含未启用的可选能力 |
| `:checkhealth vim.lsp` | 已注册 LSP 配置、Active Clients 和能力 |
| `:ConformInfo` | 当前格式化器状态、可执行文件信息和日志 |
| `:messages` | 最近的编辑器提示与错误 |
| `:set filetype?` | 当前文件类型 |
| `:pwd` | 当前工作目录 |

在当前 cpp 缓冲区也可以查看已附加客户端：

```vim
:lua vim.print(vim.lsp.get_clients({ bufnr = 0 }))
```

不要在刚切到健康报告缓冲区后，用 bufnr=0 的结果代替此前源码缓冲区状态。综合 LSP 报告中的 Active Clients 则会列出会话里的活动客户端。

### 13.2 本次报告中常见提示如何理解

| 提示 | 解释与处理顺序 |
| --- | --- |
| Not Loaded | 等待触发加载，不等于未安装 |
| Mason 没有 clangd | 本仓库使用系统 LLVM，可以正常；查 Active Client 的 Command |
| No active clients | 启动页可正常；在 cpp 文件中仍无客户端才继续排查 |
| clangd fallback / C++14 | 未取得预期编译参数，先修数据库发现与生成 |
| expected 头文件被认为未使用 | 先确认 C++23 命令与解析；示例实际使用 std::expected，不盲删 |
| c.doxygen / cpp.doxygen 未知 | 上游复合 filetype 提示；先看普通 cpp 是否正常附加 |
| CodeLLDB executable OK | 安装入口存在，实际调试还需测试 |
| LuaRocks 缺失且无插件需要它 | 当前不阻塞，可以明确关闭这项支持 |
| fish_indent 缺失 | 与 Fish 格式化有关 |
| fzf / ast-grep 缺失 | 对应扩展能力；当前普通搜索可能已通过检查 |
| Go/PHP/Ruby/Julia 等缺失 | Mason 扫描的其他语言依赖；按实际工具需求准备 |
| provider 缺失 | 对应远程插件能力；不能直接推断普通 LSP 不可用 |
| Snacks.image 工具缺失 | 图片/PDF/图表预览功能，不等于文本编辑故障 |
| which-key 前缀重叠 | 信息提示；看是否有实际冲突或重复映射 |

### 13.3 有红色 ERROR 不代表 C++ 全部不可用

本次 LuaRocks 报告同时说明没有插件需要它。若固定配置明确不使用 LuaRocks，可在现有 lazy.setup 的选项中加入：

```lua
rocks = { enabled = false },
```

这是一条选项字段，放到现有选项表里，不能单独当作完整 Lua 文件。它关闭 LuaRocks 支持，不关闭 Neovim 自带 Lua。[lazy.nvim 配置](https://lazy.folke.io/configuration)。

Snacks.image 在用户报告中是 disabled，但健康检查仍列出图形协议、ImageMagick、Ghostscript、Mermaid 工具等缺失项。只有需要这些预览能力时才安排它们，不应为了清零提示给所有 C++ 机器增加整套图形工具。[Snacks image](https://github.com/folke/snacks.nvim/blob/main/docs/image.md)。

### 13.4 原生包目录和锁文件提示

用户报告同时出现 lazy 检测到 site/pack/core，以及 vim.pack 缺锁文件。本次只读检查发现该 opt 目录为空，不能仅凭目录存在推断两个管理器正冲突地加载插件。

`nvim-pack-lock.json` 属于原生 vim.pack；`lazy-lock.json` 属于 lazy.nvim。不要为了消除提示，额外给已由 lazy.nvim 管理的插件执行另一套 vim.pack 安装流程。也不要未经确认删除整个 nvim 数据目录。

### 13.5 阅读 clangd 日志

日志中关键内容包括：是否加载数据库、最终编译命令、是否 fallback、诊断和进程退出原因。Neovim 可能把语言服务器写到 stderr 的文字记入 ERROR 级日志，但其中 I[...] 等仍可能是服务器的信息日志。

因此要读消息正文。例如 `Loaded compilation database` 是数据库发现证据；`Failed to find compilation database` 是需要处理的发现失败；`Task was cancelled` 要结合请求和后续是否正常工作判断。

修改数据库后先观察是否被重新加载；未生效时，使用安装版本提供的 :LspRestart，或退出后重新启动编辑器。删除缓存不能修复错误的编译参数。

### 13.6 最短排障顺序

1. 查看实际应用名和 stdpath，确认编辑器读取的配置。
2. 确认插件启用入口与安装状态。
3. 确认 cpp filetype 和活动 clangd 的启动命令。
4. 确认数据库包含该源文件，目录/编译器可用，标准/宏/include 参数正确。
5. 用单文件 clangd --check 对照编辑器日志。
6. 最后检查格式化规则、静态检查策略、性能与调试。

本仓库数据库同步器会检查 JSON 结构和工作目录，但不会证明每个条目的编译语义正确。真实项目仍应通过自身的 configure/build/test 验收。[clangd 排障说明](https://clangd.llvm.org/troubleshooting)。

## 14. 学习顺序与资料

### 14.1 分阶段学习，保留每一步的验收条件

| 阶段 | 学习内容 | 可以结束该阶段的证据 |
| --- | --- | --- |
| 基本编辑 | Normal/Insert、保存退出、搜索、撤销 | 能独立修改并保存文件 |
| 文件与窗口 | Buffer、分屏、查找文件和文本 | 能在两个源码文件间导航 |
| 配置 | stdpath、options、keymaps、插件规格 | 能修改一项设置并确认生效 |
| C++ 语言服务 | Extras、clangd 来源、数据库 | std::expected 等代码正确解析，K/gd/补全可用 |
| 项目构建 | VS 环境、Presets、目标和测试 | 能构建指定目标并运行 CTest |
| 调试与多机 | DAP、锁文件、机器差异 | 在目标程序验证断点，另一台机器重复验收 |

健康检查提示的数量不是毕业条件；每一步以实际功能和可复现证据为准。

### 14.2 主要依据

Lua 示例的用途在各节说明；实际配置模板和验证范围见 [部署说明](nvim-cpp.md)。以下是相关官方资料：

- [Neovim 用户手册](https://github.com/neovim/neovim/blob/master/runtime/doc/usr_02.txt)
- [Neovim Lua 指南](https://github.com/neovim/neovim/blob/master/runtime/doc/lua-guide.txt)
- [Neovim 启动与标准目录](https://github.com/neovim/neovim/blob/master/runtime/doc/starting.txt)
- [LazyVim 安装](https://www.lazyvim.org/installation)
- [LazyVim 文件结构](https://www.lazyvim.org/configuration)
- [LazyVim 通用设置](https://www.lazyvim.org/configuration/general)
- [LazyVim 插件配置](https://www.lazyvim.org/configuration/plugins)
- [LazyVim Extras](https://www.lazyvim.org/extras)
- [LazyVim clangd 扩展](https://www.lazyvim.org/extras/lang/clangd)
- [LazyVim CMake 扩展](https://www.lazyvim.org/extras/lang/cmake)
- [LazyVim Extras 的本机核对对应上游源码](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/util/extras.lua)
- [LazyVim LSP 集成源码](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/lsp/init.lua)
- [lazy.nvim 插件规格](https://lazy.folke.io/spec)
- [lazy.nvim 管理命令](https://lazy.folke.io/usage)
- [lazy.nvim 锁文件](https://lazy.folke.io/usage/lockfile)
- [Mason](https://github.com/mason-org/mason.nvim)
- [clangd 工程设置](https://clangd.llvm.org/installation#project-setup)
- [CMake 编译数据库导出](https://cmake.org/cmake/help/latest/variable/CMAKE_EXPORT_COMPILE_COMMANDS.html)
