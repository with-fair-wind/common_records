# Windows Neovim 现代 C++ 开发环境

首次学习请先阅读 [Neovim / LazyVim 使用与配置教程](nvim-lazyvim-guide.md)，其中详细区分官方流程、Extras 启用入口与系统 LLVM 定制。

这套脚本把配置存入 Git，在多台 Windows 电脑上部署相同的 LazyVim 工作流。默认应用名为 `nvim-cpp`，使用 `NVIM_APPNAME` 与原有 `nvim` 配置、插件和缓存分开。使用者运行安装脚本时才部署；仓库示例验证不会安装到真实用户配置目录。

适用范围：Windows 11 x64、PowerShell 7、MSVC 或 clang-cl、CMake + Ninja、C++23。支持 x64/x86 目标，启动脚本的主机工具默认为 x64。ARM64、WSL、MinGW 工具链不属于这一版自动化范围。

LazyVim、starter 与 lazy.nvim 的职责见教程的 [组件关系](nvim-lazyvim-guide.md#1-组件关系)；本页集中记录本仓库的部署操作。

## 多机共享的边界

| 层次 | 保存内容 | 多台电脑如何复用 |
| --- | --- | --- |
| 编辑器共享层 | Lua、插件扩展、快捷键、验证过的 lazy-lock.json | 同步这个仓库，运行部署脚本 |
| 本机层 | VS 安装路径、LLVM 路径、SDK、代理、字体 | 自动发现 VS；必要时填写 local.lua |
| 项目层 | CMakePresets.json、.clang-format、.clang-tidy | 跟随项目仓库；保留项目原有规则 |
| 生成物 | build、compile_commands.json、插件缓存、PDB | 在每台机器本地生成 |

`compile_commands.json` 中常含绝对路径，因此不能直接拿 A 电脑生成的文件给 B 电脑使用。C++23 标准由项目目标的 `cxx_std_23` 等构建设置决定，编辑器不全局追加 `-std`、`-I`、`-D`。

## 文件入口

| 文件 | 职责 |
| --- | --- |
| [NvimCpp.Common.ps1](../../scripts/nvim/NvimCpp.Common.ps1) | 公共辅助函数：配置路径、外部命令检查、VS 发现和环境初始化，不单独运行 |
| [Install-NvimCpp.ps1](../../scripts/nvim/Install-NvimCpp.ps1) | 可选 Scoop 安装、配置部署、更新备份、导入锁文件 |
| [Start-NvimCpp.ps1](../../scripts/nvim/Start-NvimCpp.ps1) | 发现 VS、初始化开发环境、设置应用名并启动 nvim |
| [Update-NvimCppDatabase.ps1](../../scripts/nvim/Update-NvimCppDatabase.ps1) | 校验并同步当前构建目录的编译数据库 |
| [Test-NvimCppEnvironment.ps1](../../scripts/nvim/Test-NvimCppEnvironment.ps1) | 检查版本、PATH、VS 环境和指定源文件的 clangd 解析 |
| [config/](../../scripts/nvim/config/) | 共享 LazyVim Lua 配置 |
| [C++23 示例](../../scripts/nvim/examples/cpp23/) | MSVC/clang-cl 独立构建目录与 CTest 验收样例 |
| [回归验证](../../scripts/nvim/tests/Test-NvimCppScripts.ps1) | 隔离验证部署、备份和数据库行为 |

以下命令均在 **PowerShell 7** 中执行。先进入本仓库根目录；路径按实际位置调整：

```powershell
Set-Location D:\code\pwsh\common_records
$repo = (Get-Location).Path
```

## 第一台电脑安装

先安装 Visual Studio 或 Build Tools 的“使用 C++ 的桌面开发”工作负载，包含 MSVC x86/x64 工具和 Windows SDK。该大型工具链由 VS Installer 管理，脚本只发现和使用已有安装。也请准备 PowerShell 7、Scoop，以及能访问 GitHub 的网络。

当前配置依据的 LazyVim 要求 Neovim ≥ 0.11.2、Git ≥ 2.19，并要求 tree-sitter CLI、C 编译器和 curl；完整依赖见 [LazyVim 官方要求](https://www.lazyvim.org/)。Neovim 需要 LuaJIT 构建。CMake 示例最低为 3.21；LLVM 和 VS 应选择能处理项目实际 C++23 特性的版本。

预演后安装：

```powershell
.\scripts\nvim\Install-NvimCpp.ps1 -InstallTools -WhatIf
.\scripts\nvim\Install-NvimCpp.ps1 -InstallTools
```

工具清单为 Git、Neovim、ripgrep、fd、lazygit、LLVM、CMake、Ninja、tree-sitter CLI 和 Python（供 CMake 扩展的 Python 工具使用）。现有命令已能找到时跳过对应软件包；不自动升级已有软件。LLVM 按 clangd、clang-format、clang-tidy、clang-cl 四个命令检查。若软件包已安装却缺少命令，安装后的复查会失败并要求修正 PATH。

如果工具已由公司镜像、Scoop 离线 Bundle 或其他安装方式准备好，只部署配置：

```powershell
.\scripts\nvim\Install-NvimCpp.ps1
```

安装脚本不下载插件；默认配置路径是 `%LOCALAPPDATA%\nvim-cpp`。若设置了 `XDG_CONFIG_HOME`，则使用它下面的 `nvim-cpp`。数据目录由 Neovim 的 `stdpath('data')` 决定，默认通常为 `%LOCALAPPDATA%\nvim-cpp-data`。不要在不同电脑硬编码这些展开后的个人路径。

检查依赖并首次启动：

```powershell
.\scripts\nvim\Test-NvimCppEnvironment.ps1
.\scripts\nvim\Start-NvimCpp.ps1 -ProjectPath .\scripts\nvim\examples\cpp23
```

首次启动会引导 lazy.nvim，下载 LazyVim 及插件；Mason 可能另行下载 CodeLLDB、CMake 语言服务和辅助工具。等待安装完成，然后执行：

```vim
:Lazy
:LazyHealth
:checkhealth vim.lsp
:Mason
```

Treesitter 的解析器安装需要 C 编译器，所以首次启动同样通过 VS 启动脚本进入开发环境。Windows Terminal 的字体需要自行选择已安装的 Nerd Font；可参考仓库 [字体脚本](../../scripts/scoop/nerd-fonts-install.ps1)。

配置直接导入 `lang.clangd`、`lang.cmake`、`dap.core`，无需再到 `:LazyExtras` 重复添加。Blink 使用 LazyVim 默认方案；项目升级时应重新查看默认补全后端。`lang.cmake` 已引入 cmake-tools.nvim，本配置覆盖其选项。[官方 CMake 扩展](https://www.lazyvim.org/extras/lang/cmake)。

## 验收一个 C++23 工程

先在当前 PowerShell 中初始化 VS 环境；`-EnvironmentOnly` 不启动编辑器：

```powershell
& "$repo\scripts\nvim\Start-NvimCpp.ps1" -EnvironmentOnly
Set-Location "$repo\scripts\nvim\examples\cpp23"

cmake --preset msvc-debug
cmake --build --preset msvc-debug
ctest --preset msvc-debug

& "$repo\scripts\nvim\Update-NvimCppDatabase.ps1" `
    -ProjectPath . -BuildDirectory build\msvc-debug

& "$repo\scripts\nvim\Test-NvimCppEnvironment.ps1" `
    -RequireDeveloperEnvironment `
    -SourceFile src\main.cpp -BuildDirectory build\msvc-debug

& "$repo\scripts\nvim\Start-NvimCpp.ps1" -ProjectPath .
```

`-EnvironmentOnly` 必须像上述方式在当前会话调用；若用 `pwsh -File ... -EnvironmentOnly`，环境只保留在那个子进程中。使用新终端时需要重新初始化。脚本通过 VS 的 Developer PowerShell 模块设置环境。[微软 Developer PowerShell 说明](https://learn.microsoft.com/en-us/visualstudio/ide/reference/command-prompt-powershell?view=visualstudio)。

示例程序使用 `std::expected`，CTest 应有 1 个测试通过。MSVC/clang-cl 示例目标设置 `/utf-8`，避免中文 Windows 系统代码页影响源码解析。该示例只能证明所用特性可编译，不代表编译器已支持所有 C++23 特性或模块。

要试用 clang-cl，保持独立目录：

```powershell
cmake --preset clangcl-debug
cmake --build --preset clangcl-debug
ctest --preset clangcl-debug
& "$repo\scripts\nvim\Update-NvimCppDatabase.ps1" `
    -ProjectPath . -BuildDirectory build\clangcl-debug
```

已有项目应沿用本项目的构建入口。可参考示例 Presets 合并 Ninja 配置或在 `CMakeUserPresets.json` 中继承已有配置，并保留工具链文件、依赖路径、宏、生成头文件、ABI 和功能开关。示例只声明 CXX；含 C 的项目还需选择相应的 `CMAKE_C_COMPILER`。不要直接覆盖项目原有 Presets、.clang-format 或 .clang-tidy。

## 编译数据库与日常工作流

clangd 依据真实编译数据库解析代码。Ninja 支持 `CMAKE_EXPORT_COMPILE_COMMANDS`；Visual Studio 生成器不直接支持这个导出开关。若正式工程使用 VS 生成器，可增加参数和依赖一致的 Ninja 工具配置。[CMake 官方说明](https://cmake.org/cmake/help/latest/variable/CMAKE_EXPORT_COMPILE_COMMANDS.html)。

进入项目根目录后，可按以下顺序操作：

1. `:CMakeSelectConfigurePreset` 选择配置。
2. `:CMakeGenerate` 生成构建系统并复制数据库到当前项目根目录。
3. `:CMakeSelectBuildPreset`、`:CMakeSelectBuildTarget` 选择构建预设和目标。
4. `:CMakeBuild` 构建；`:CMakeSelectLaunchTarget`、`:CMakeRun` 运行。
5. `:CMakeRunTest` 执行项目测试。

配置用 `copy` 而不是符号链接，以避免 Windows 符号链接权限问题。插件以当前工作目录作为数据库复制目标，因此应从 CMake 源码根启动 nvim，并在该目录执行构建命令。通过命令行 configure 时，调用数据库同步脚本。插件功能及选项见 [cmake-tools.nvim](https://github.com/Civitasv/cmake-tools.nvim)。

根目录的 `compile_commands.json` 是可重新生成的活动数据库。同步脚本会替换它，拒绝空数组、缺字段或编译工作目录不存在的文件，并支持 `-WhatIf`；已有根数据库为链接时拒绝覆盖。它不会合并多个构建配置。成功 configure 后才同步，不能把配置失败留下的旧数据库当作新结果。

Debug、Release 和不同编译器使用不同 build 子目录。每次切换都同步正确数据库，并在 Neovim 中执行 `:LspRestart`（若当前版本提供）或重新启动编辑器。项目应忽略：

```gitignore
/build/
/compile_commands.json
/CMakeUserPresets.json
/.cache/
```

全局配置不生成 `.clangd`。根目录数据库可被发现时通常不需要它；团队决定固定某个构建目录时才添加项目级 `CompileFlags.CompilationDatabase`。不要同时让该字段和根目录复制策略指向不同的配置。[clangd 工程设置](https://clangd.llvm.org/installation#project-setup)。

本配置的快捷键（leader 默认空格）：

| 快捷键 | 功能 |
| --- | --- |
| Space m p | 选择 configure preset |
| Space m g | Configure |
| Space m b | 构建 |
| Space m t | 选择目标 |
| Space m r | 运行 |
| Space m d | DAP 调试 |
| Space m s | CTest |

`gd`、`K`、`Space c r`、`Space c a` 等导航和重构沿用 LazyVim；按空格查看实际绑定。需要自动保存格式化时可用 LazyVim 的格式化开关；具体格式来自项目的 `.clang-format`。

## 本机差异与大型项目

clangd 与 clang-format 在 Neovim 启动时从系统 PATH 解析并保存绝对路径；clangd 设置 `mason=false`，Mason 的 PATH 使用 append，减少工具链版本交叉。CMake 语言服务和 CodeLLDB 仍可由 Mason 管理。

有多份 LLVM、代理或性能差异时，将部署目录的 `lua/config/local.example.lua` 复制成同目录 `local.lua`，按需填写：

```lua
return {
  clangd = "D:/tools/llvm/bin/clangd.exe",
  clang_format = "D:/tools/llvm/bin/clang-format.exe",
  clang_tidy = true,
  clangd_args = { "-j=4" },
}
```

这类个人路径不提交共享仓库。更新脚本只覆盖受管理模板文件，保留部署目录的 `local.lua` 和其他附加文件。默认关闭实时 clang-tidy；先确认标准库与项目头文件解析正确，再启用并按项目 `.clang-tidy` 检查。示例只启用了少量明确的规则。

`--query-driver` 不作为 MSVC 缺标准库的默认补丁。出现 `<vector>`、`<expected>` 等找不到的错误，先检查 VS/SDK、INCLUDE、数据库和 clangd 的实际命令；不要把 SDK 版本目录写死到全局 Lua。

多份 VS 时：

```powershell
& "$repo\scripts\nvim\Start-NvimCpp.ps1" `
    -ProjectPath D:\Projects\MyProject `
    -VsPath 'C:\Program Files\Microsoft Visual Studio\2022\Community' -Arch x64
```

自动发现选取含 x86/x64 C++ 工作负载的最新安装。已由其他工具正确设置环境、或需要使用非 VS 环境时，才用 `-SkipDeveloperEnvironment`。该参数不会自动补齐 INCLUDE/LIB。启动器会恢复调用者原有 NVIM_APPNAME 和工作目录，VS 环境则保留在当前 PowerShell 进程中，不修改持久用户 PATH。

## 第二台及后续电脑：版本复用

只同步 Lua 不能保证插件版本相同。第一台通过完整验收后，将其 `lazy-lock.json` 保存为仓库中的受控文件，例如 `scripts/nvim/locks/lazy-lock.json`（自行创建 locks 目录）：

```powershell
New-Item -ItemType Directory -Path "$repo\scripts\nvim\locks" -Force
Copy-Item "$env:LOCALAPPDATA\nvim-cpp\lazy-lock.json" `
    "$repo\scripts\nvim\locks\lazy-lock.json"
```

若使用 XDG_CONFIG_HOME，以实际部署路径为准。审查并提交锁文件后，在新电脑运行：

```powershell
.\scripts\nvim\Install-NvimCpp.ps1 -InstallTools `
    -LockFile .\scripts\nvim\locks\lazy-lock.json
.\scripts\nvim\Start-NvimCpp.ps1 -ProjectPath D:\Projects\MyProject
```

首次安装插件时使用锁文件。已有机器导入锁文件后，在 Neovim 中执行 `:Lazy restore`，而不是用 `:Lazy update` 作为同步步骤。更新团队插件版本应先在一台机器上验证，再导出新锁文件并推广。[lazy.nvim 锁文件说明](https://lazy.folke.io/usage/lockfile)。

工具版本也应记录，可将环境检查输出保存成机器清单：

```powershell
.\scripts\nvim\Test-NvimCppEnvironment.ps1 *> .\nvim-cpp-machine.local.txt
```

清单含个人路径，不宜直接提交。团队至少约定 Neovim、LLVM、CMake、Ninja、VS 工具集和 SDK 版本，并在各机重新验收。`-InstallTools` 用当前 Scoop 软件包版本，不保证多次在线安装获取同一个版本；需要精确复现时使用同一套固定版本安装包/离线 Bundle。插件 Git 锁文件也不锁定 Mason 二进制、Treesitter 解析器、VS、SDK 或其他外部资源。

## 更新与恢复

```powershell
.\scripts\nvim\Install-NvimCpp.ps1 -Update -WhatIf
.\scripts\nvim\Install-NvimCpp.ps1 -Update
```

内容相同的重复安装不写文件、不创建备份。共享模板发生变化时，普通安装拒绝覆盖；显式 `-Update` 会先把完整配置复制为同级 `nvim-cpp.backup-时间-随机标识`，再覆盖变更的模板文件。只调整锁文件同样先备份。此更新采用覆盖保留策略，不删除旧附加文件；废弃的个人插件文件需要使用者自行审查。关闭编辑器后再更新。

恢复时，可在确认目录路径后，把当前配置重命名为另一个保留目录，再将选定备份复制回原配置路径。插件代码可能需要配合恢复的锁文件执行 `:Lazy restore`。备份覆盖配置文件，不包括 nvim 数据目录或系统工具；不要把它当作完整离线环境备份。

## 调试与离线部署

DAP 基础及 CodeLLDB 集成沿用 LazyVim，检查 `:Mason` 的 codelldb 安装状态，选择 Debug 可执行文件、设置断点后验证变量和调用栈。示例可执行文件在 `build/msvc-debug/nvim_cpp_smoke.exe` 或 clang-cl 对应目录。

LLDB 的 PDB 支持仍可能存在缺陷；复杂 CAD/ZRX DLL、宿主进程附加和符号问题建议保留 VS 调试器。不能把安装成功等同于所有目标都可正确调试。[CodeLLDB Windows 说明](https://github.com/vadimcn/codelldb/wiki/Windows)。

本套配置支持多机在线引导；复制源码配置并不等于完成离线部署。工具可复用仓库 [Scoop 离线部署流程](../scoop/offline-bundle-usage.md)，但额外还需在有网同平台机器准备插件仓库、lazy.nvim、Mason 资源、解析器和构建工具，检查缓存中的机器路径、动态库与版本，并在断网机器验收。这一版不提供这些 Neovim 资源的完整离线打包器。

代理由使用者为 Git、Scoop 和下载程序配置；不要把用户名、密码或私人代理固定写进共享脚本。

## 排障与验证范围

| 症状 | 优先检查 |
| --- | --- |
| Lua 初始化失败 | Neovim 版本、Git、下载网络、插件版本与锁文件 |
| C/C++ 无 LSP | 部署的 AppName、`:checkhealth vim.lsp`、clangd 路径 |
| 标准库找不到 | VS 工作负载/SDK、INCLUDE、正确的活动数据库 |
| CMake 选错配置 | configure/build preset、根数据库、当前工作目录 |
| Treesitter 安装失败 | tree-sitter CLI、C 编译器、VS 环境和下载网络 |
| CMake 辅助工具安装失败 | Python、Mason 日志和下载环境 |
| 格式化版本不一致 | `:ConformInfo`、实际 clang-format 路径和项目规则 |
| 多份工具互相遮蔽 | 环境检查列出的 PATH 候选，本机 local.lua |
| PDB 断点或变量异常 | Debug 符号、CodeLLDB 输出、改用 VS 检查 |

仓库自测（在根目录运行，不写入真实用户配置，也不安装软件）：

```powershell
.\scripts\nvim\tests\Test-NvimCppScripts.ps1
nvim --headless -u NONE -l scripts/nvim/tests/check-config.lua
```

2026-10-12 已在本机验证：PowerShell 部署/数据库回归、Lua 语法和配置选项、VS 自动发现、MSVC Debug 与 clang-cl Debug 构建、各 1 个 CTest 测试、两个数据库下单文件 clangd 解析，以及示例 clang-format/clang-tidy。工具为 Neovim 0.12.6、LLVM 23.1.3、CMake 4.4.4、Ninja 1.13.2、MSVC 19.51。

本机尚未安装 tree-sitter CLI；未进行真实用户目录部署、完整插件联网安装或 DAP 交互验收。Lua 自测使用替代插件模块，只验证语法和选项，不证明插件集成运行。示例验证只覆盖一个翻译单元；使用者仍应在每台电脑按上述步骤检查实际项目和编辑器健康状态。
