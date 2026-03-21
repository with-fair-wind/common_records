# VS Code 扩展清单分类、配置建议与精简建议

> 基于 `extensions.json`（已安装）与 `Install-VSCodeExtensions.ps1`（计划安装）整理。  
> 你的当前清单明显偏“全家桶”，包含大量同类主题/图标/语言链路重复项，建议做分层（核心 + 按场景启用）。

## 1) 按功能分类（详细）

## A. 基础体验与效率增强（建议保留）

- `alefragnani.project-manager`：多项目快速切换，适合多仓库开发。
- `christian-kohler.path-intellisense`：补全路径，减少导入/引用错误。
- `usernamehw.errorlens`：把诊断信息直接显示在行内，改错很高效。
- `w88975.code-translate`：代码注释/片段翻译辅助。
- `aooiu.any-reader`：多格式内容读取。
- `ms-ceintl.vscode-language-pack-zh-hans`：中文语言包（界面本地化）。

## B. 格式化、文档与写作（建议保留）

- `esbenp.prettier-vscode`：前端/通用格式化核心。
- `davidanson.vscode-markdownlint`：Markdown 规范检查。
- `yzhang.markdown-all-in-one`：Markdown 编辑增强（目录、快捷键等）。
- `shd101wyy.markdown-preview-enhanced`：高级 Markdown 预览与导出。
- `yzane.markdown-pdf`：Markdown 导出 PDF。
- `cschlosser.doxdocgen`：自动生成注释模板（尤其 C/C++）。
- `adpyke.codesnap`：代码截图分享。

## C. Python 生态（建议保留，需配置）

- `ms-python.python`：Python 核心扩展（解释器、运行、调试入口）。
- `ms-python.vscode-pylance`：类型检查与智能补全。
- `ms-python.debugpy`：调试支持。
- `ms-python.black-formatter`：Black 格式化。
- `ms-python.isort`：import 排序。
- `ms-python.vscode-python-envs`：虚拟环境管理。
- `ms-toolsai.jupyter`：Jupyter Notebook 支持。
- `ms-toolsai.jupyter-keymap`、`ms-toolsai.jupyter-renderers`、`ms-toolsai.vscode-jupyter-cell-tags`、`ms-toolsai.vscode-jupyter-slideshow`：Jupyter 辅助组件。

## D. C/C++ / 构建工具链（按实际项目保留）

- `ms-vscode.cpptools`：C/C++ 语言服务与调试。
- `ms-vscode.cpptools-extension-pack`、`ms-vscode.cpptools-themes`：cpptools 扩展包与配套主题。
- `llvm-vs-code-extensions.vscode-clangd`：clangd 语义服务（与 cpptools 有功能重叠）。
- `llvm-vs-code-extensions.lldb-dap`、`vadimcn.vscode-lldb`：LLDB 调试（二者也有重叠）。
- `jeff-hykin.better-cpp-syntax`、`chris-noring.cpp-snippets`：语法高亮和代码片段。
- `ms-vscode.cmake-tools`、`kylinideteam.cmake-intellisence`、`josetr.cmake-language-support-vscode`：CMake 工具链（存在重叠）。
- `ms-vscode.makefile-tools`：Makefile 工程支持。
- `danielpinto8zz6.c-cpp-project-generator`：C/C++ 项目模板生成。
- `tboox.xmake-vscode`：XMake 项目支持。
- `galarius.vscode-opencl`：OpenCL 开发支持。
- `willasm.rc-script`：Windows rc 脚本支持。

## E. Java 生态（按实际项目保留）

- `redhat.java`：Java 语言服务核心。
- `vscjava.vscode-java-pack`：Java 扩展打包（通常已包含常用组件）。
- `vscjava.vscode-java-debug`、`vscjava.vscode-java-test`：调试/测试支持。
- `vscjava.vscode-maven`、`vscjava.vscode-gradle`：构建工具支持。
- `vscjava.vscode-java-dependency`（你当前已安装）；脚本中写的是 `vscjava.vscode-java-dependency-analyser`（疑似旧/误写）。

## F. PowerShell / .NET（按实际项目保留）

- `ms-vscode.powershell`：PowerShell 语言支持与调试。
- `ms-dotnettools.vscode-dotnet-runtime`：按需安装/管理 .NET 运行时（多扩展依赖）。

## G. 远程开发与容器（按工作方式保留）

- `ms-vscode.remote-explorer`：远程资源入口。
- `ms-vscode-remote.remote-ssh`、`ms-vscode-remote.remote-ssh-edit`：SSH 远程开发。
- `ms-vscode-remote.remote-wsl`：WSL 开发。
- `ms-vscode-remote.remote-containers`、`ms-azuretools.vscode-containers`、`ms-azuretools.vscode-docker`：容器/Dev Containers/Docker 工作流。

## H. Git 与协作（建议保留）

- `mhutchie.git-graph`：可视化提交图。
- `donjayamanne.githistory`：Git 历史浏览（与 Git Graph 有一定重叠）。
- `github.copilot-chat`：AI 协作（需登录授权）。
- `wakatime.vscode-wakatime`：编码时间统计（需 API Key）。

## I. LeetCode 刷题链路（建议只留一套）

- `leetcode.vscode-leetcode`：主扩展（登录、题库、提交）。
- `ccagml.vscode-leetcode-problem-rating`：难度/评分增强。
- `wangtao0101.debug-leetcode`：调试增强。
- `xaviercai.vscode-leetcode-cpp-debug`：C++ 调试增强。
- `bat67.leetcode-extension-pack`：LeetCode 扩展包（可能重复安装同类功能）。

## J. 界面主题/图标/视觉效果（可大幅精简）

- 主题类（只能同时启用一个）：  
  `akamud.vscode-theme-onelight`、`azemoh.one-monokai`、`dracula-theme.theme-dracula`、`jdinhlife.gruvbox`、`mateocerquetella.xcode-12-theme`、`mrpbennett.atlantic-night`、`mvllow.rose-pine`、`pawelgrzybek.gatito-theme`、`piousdeer.adwaita-theme`、`robbowen.synthwave-vscode`、`sdras.night-owl`、`teabyii.ayu`、`tinkertrain.theme-panda`、`wicked-labs.sequoia`、`zhuangtongfa.material-theme`、`alexdauenhauer.catppuccin-noctis`、`chirtlelovesdolls.nebula-theme`、`ddiu8081.moegi-theme`、`harryhopkinson.vim-theme`、`levampire.buttur`、`tearz.tearz`。
- 图标类（也只能启用一个）：  
  `pkief.material-icon-theme`、`file-icons.file-icons`、`catppuccin.catppuccin-vsc-icons`、`beardedbear.beardedicons`、`eliverlara.sweet-vscode-icons`、`tal7aouy.icons`、`alexdauenhauer.catppuccin-noctis-icons`。
- 视觉效果/定制：  
  `be5invis.vscode-custom-css`、`s-nlf-fh.glassit`、`drcika.apc-extension`（可能影响稳定性和升级体验）。

## K. 其他工具

- `hediet.vscode-drawio`：在编辑器内画图与维护架构图。
- `ms-vscode.hexeditor`：二进制/十六进制查看编辑。
- `rimuruchan.vscode-fix-checksums-next`：修复校验相关问题（非常场景化）。
- `formulahendry.code-runner`：一键运行代码（与语言专用运行链路常重叠）。
- `fittentech.fitten-code-enterprise`、`thomaz.preparing`：用途依赖个人工作流，建议按实际频率决定保留。

---

## 2) 需要重点配置的扩展（含配置建议）

## Python + Jupyter

建议在工作区 `settings.json` 配置：

```json
{
  "python.defaultInterpreterPath": ".venv/Scripts/python.exe",
  "python.terminal.activateEnvironment": true,
  "python.analysis.typeCheckingMode": "basic",
  "editor.formatOnSave": true,
  "[python]": {
    "editor.defaultFormatter": "ms-python.black-formatter",
    "editor.codeActionsOnSave": {
      "source.organizeImports": "explicit"
    }
  },
  "jupyter.askForKernelRestart": false
}
```

说明：
- `black` 与 `isort` 最好与项目工具链统一（建议配合 `pyproject.toml`）。
- 如果你不常用 Notebook，可以只保留 `ms-toolsai.jupyter`，其余辅助组件按需启用。

## C/C++（cpptools 与 clangd 二选一主链路）

建议二选一，避免重复索引和诊断冲突：

- 方案 1（更省心）：`ms-vscode.cpptools` 为主。
- 方案 2（语义更强）：`llvm-vs-code-extensions.vscode-clangd` 为主，并关闭 cpptools 智能感知。

如果使用 clangd，可加：

```json
{
  "C_Cpp.intelliSenseEngine": "Disabled",
  "clangd.arguments": [
    "--background-index",
    "--clang-tidy"
  ]
}
```

## Java

建议确保本机 JDK 路径明确，避免语言服务启动失败：

```json
{
  "java.configuration.runtimes": [
    {
      "name": "JavaSE-17",
      "path": "D:/dev/jdk-17"
    }
  ],
  "java.import.gradle.enabled": true,
  "java.import.maven.enabled": true
}
```

## Remote / Docker

需要额外配置：
- `remote-ssh`：`~/.ssh/config`、密钥权限、主机别名。
- `remote-containers` / `vscode-docker`：本机 Docker Desktop 可用，WSL2 后端已开启（Windows）。

## LeetCode

需要登录并配置默认语言：

```json
{
  "leetcode.defaultLanguage": "cpp"
}
```

如你主要刷 C++，优先保留主扩展 + 一个调试增强扩展即可。

## WakaTime

首次使用需配置 API Key（命令面板登录），否则仅安装不生效。

## Prettier / Markdown

建议统一格式化策略，避免与其他 formatter 冲突：

```json
{
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "[markdown]": {
    "editor.defaultFormatter": "yzhang.markdown-all-in-one"
  }
}
```

> 如果你希望 Markdown 也走 Prettier，可把 `[markdown]` 的 formatter 改回 Prettier。

---

## 3) 建议“可精简/不必要”的扩展列表（按你当前清单）

> 判定标准：重复功能、低使用频率、可能影响稳定性、或仅视觉用途过多。

## A. 主题类（建议保留 2~4 个常用，其余可卸载）

可考虑移除（示例，优先删不常切换的）：

- `akamud.vscode-theme-onelight`
- `azemoh.one-monokai`
- `ddiu8081.moegi-theme`
- `harryhopkinson.vim-theme`
- `mateocerquetella.xcode-12-theme`
- `mrpbennett.atlantic-night`
- `pawelgrzybek.gatito-theme`
- `piousdeer.adwaita-theme`
- `teabyii.ayu`
- `tinkertrain.theme-panda`
- `wicked-labs.sequoia`
- `chirtlelovesdolls.nebula-theme`
- `levampire.buttur`
- `tearz.tearz`

## B. 图标类（建议只保留 1 个）

建议仅保留你最喜欢的一个，比如 `pkief.material-icon-theme`。其余可删：

- `file-icons.file-icons`
- `beardedbear.beardedicons`
- `eliverlara.sweet-vscode-icons`
- `tal7aouy.icons`
- `catppuccin.catppuccin-vsc-icons`
- `alexdauenhauer.catppuccin-noctis-icons`

## C. C/C++ 重复链路（建议精简）

- `llvm-vs-code-extensions.vscode-clangd` 与 `ms-vscode.cpptools` 二选一主力。
- `llvm-vs-code-extensions.lldb-dap` 与 `vadimcn.vscode-lldb` 二选一。
- `kylinideteam.cmake-intellisence`、`josetr.cmake-language-support-vscode` 与 `ms-vscode.cmake-tools` 有重叠，建议只留后者或你最常用的一套。
- `chris-noring.cpp-snippets`、`jeff-hykin.better-cpp-syntax` 非必需，按习惯保留。

## D. LeetCode 重复链路（建议精简）

建议保留：
- `leetcode.vscode-leetcode`
- `ccagml.vscode-leetcode-problem-rating`（可选）
- `wangtao0101.debug-leetcode` 或 `xaviercai.vscode-leetcode-cpp-debug`（二选一）

可考虑移除：
- `bat67.leetcode-extension-pack`（扩展包通常带来重复）
- 上述二选一中未选的一项

## E. 容器/远程按场景删减

如果你不用 WSL 或远程 SSH 或 Dev Containers，可删对应组件：
- 不用 WSL：`ms-vscode-remote.remote-wsl`
- 不用 SSH：`ms-vscode-remote.remote-ssh`、`ms-vscode-remote.remote-ssh-edit`
- 不用容器：`ms-vscode-remote.remote-containers`、`ms-azuretools.vscode-containers`、`ms-azuretools.vscode-docker`

## F. 可能不必要或高风险定制类

- `be5invis.vscode-custom-css`：修改工作台样式，升级后易失效或触发安全提示。
- `drcika.apc-extension`：深度 UI 定制，可能引入兼容问题。
- `s-nlf-fh.glassit`：视觉效果类，非生产力刚需。
- `rimuruchan.vscode-fix-checksums-next`：仅在特定异常场景才需要。
- `formulahendry.code-runner`：若你已有成熟语言调试/任务链路，可移除。

---

## 4) 脚本与已装清单中的 ID 差异（建议修正）

你的安装脚本里有几处扩展 ID 疑似写法不一致，会导致安装失败或装到旧项：

- 脚本：`ccagml.vscode-leetcode-problem-ratings`  
  建议：`ccagml.vscode-leetcode-problem-rating`
- 脚本：`shd101wyy.markdown-preview-enhance`  
  建议：`shd101wyy.markdown-preview-enhanced`
- 脚本：`rimuruchan.vscode-fix-checksums-needed`  
  建议：`rimuruchan.vscode-fix-checksums-next`
- 脚本：`vscjava.vscode-java-dependency-analyser`  
  建议：`vscjava.vscode-java-dependency`
- 脚本：`coltwillcox.synthwave-x-fluoromachine`  
  已装为：`webrender.synthwave-x-fluoromachine`（建议以可安装成功的 ID 为准）

---

## 5) 最小推荐保留集（实用版）

如果你想从“全家桶”降到“高效稳定”，可先保留：

- 基础：`project-manager`、`path-intellisense`、`errorlens`、`prettier`、`markdownlint`
- Python：`python`、`pylance`、`black-formatter`、`isort`、`jupyter`
- C/C++：`cpptools` + `cmake-tools`（或改为 clangd 方案）
- Java（若需要）：`vscode-java-pack` + `redhat.java`
- 远程（按需）：`remote-ssh` / `remote-wsl` / `remote-containers`
- Git：`git-graph`（`githistory` 可选）
- 主题图标：主题 2~4 个 + 图标 1 个

这样通常能把扩展数量从 100+ 降到 25~40，启动速度与稳定性会明显更好。

