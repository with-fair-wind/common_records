# 批量安装 VS Code / Cursor 扩展
# 使用: .\Install-VSCodeExtensions.ps1
# 若使用 Cursor，可先设置: $env:VSCODE_PATH = "cursor"

$ErrorActionPreference = "Stop"

# 若在 Cursor 下运行，可取消下面注释并改为 cursor
# $codeCmd = "cursor"
$codeCmd = "code"

$extensions = @(
    "adpyke.codesnap",
    "akamud.vscode-theme-onelight",
    "alefragnani.project-manager",
    "alexdauenhauer.catppuccin-noctis",
    "alexdauenhauer.catppuccin-noctis-icons",
    "aooiu.any-reader",
    "asvetliakov.vscode-neovim",
    "azemoh.one-monokai",
    "bat67.leetcode-extension-pack",
    "be5invis.vscode-custom-css",
    "beardedbear.beardedicons",
    "buuug7.gbk2utf8",
    "catppuccin.catppuccin-vsc",
    "catppuccin.catppuccin-vsc-icons",
    "ccagml.vscode-leetcode-problem-ratings",
    "chirtlelovesdolls.nebula-theme",
    "chris-noring.cpp-snippets",
    "christian-kohler.path-intellisense",
    "coltwillcox.synthwave-x-fluoromachine",
    "cschlosser.doxdocgen",
    "danielpinto8zz6.c-cpp-project-generator",
    "davidanson.vscode-markdownlint",
    "ddiu8081.moegi-theme",
    "donjayamanne.githistory",
    "dracula-theme.theme-dracula",
    "drcika.apc-extension",
    "eliverlara.sweet-vscode-icons",
    "esbenp.prettier-vscode",
    "file-icons.file-icons",
    "fittentech.fitten-code-enterprise",
    "formulahendry.code-runner",
    "galarius.vscode-opencl",
    "github.copilot-chat",
    "harryhopkinson.vim-theme",
    "hediet.vscode-drawio",
    "james-yu.latex-workshop",
    "jdinhlife.gruvbox",
    "jeff-hykin.better-cpp-syntax",
    "josetr.cmake-language-support-vscode",
    "kisstkondoros.vscode-gutter-preview",
    "kylinideteam.cmake-intellisence",
    "leetcode.vscode-leetcode",
    "levampire.buttur",
    "llvm-vs-code-extensions.lldb-dap",
    "llvm-vs-code-extensions.vscode-clangd",
    "mateocerquetella.xcode-12-theme",
    "mhutchie.git-graph",
    "mrpbennett.atlantic-night",
    "ms-azuretools.vscode-containers",
    "ms-azuretools.vscode-docker",
    "ms-ceintl.vscode-language-pack-zh-hans",
    "ms-dotnettools.vscode-dotnet-runtime",
    "ms-python.black-formatter",
    "ms-python.debugpy",
    "ms-python.isort",
    "ms-python.python",
    "ms-python.vscode-pylance",
    "ms-python.vscode-python-envs",
    "ms-toolsai.jupyter",
    "ms-toolsai.jupyter-keymap",
    "ms-toolsai.jupyter-renderers",
    "ms-toolsai.vscode-jupyter-cell-tags",
    "ms-toolsai.vscode-jupyter-slideshow",
    "ms-vscode.cmake-tools",
    "ms-vscode.cpptools",
    "ms-vscode.cpptools-extension-pack",
    "ms-vscode.cpptools-themes",
    "ms-vscode.hexeditor",
    "ms-vscode.makefile-tools",
    "ms-vscode.powershell",
    "ms-vscode.remote-explorer",
    "ms-vscode-remote.remote-containers",
    "ms-vscode-remote.remote-ssh",
    "ms-vscode-remote.remote-ssh-edit",
    "ms-vscode-remote.remote-wsl",
    "mvllow.rose-pine",
    "pawelgrzybek.gatito-theme",
    "piousdeer.adwaita-theme",
    "pkief.material-icon-theme",
    "redhat.java",
    "rimuruchan.vscode-fix-checksums-needed",
    "robbowen.synthwave-vscode",
    "sdras.night-owl",
    "shd101wyy.markdown-preview-enhance",
    "s-nlf-fh.glassit",
    "tal7aouy.icons",
    "tboox.xmake-vscode",
    "teabyii.ayu",
    "tearz.tearz",
    "thomaz.preparing",
    "tinkertrain.theme-panda",
    "usernamehw.errorlens",
    "vadimcn.vscode-lldb",
    "vscjava.vscode-gradle",
    "vscjava.vscode-java-debug",
    "vscjava.vscode-java-dependency-analyser",
    "vscjava.vscode-java-pack",
    "vscjava.vscode-java-test",
    "vscjava.vscode-maven",
    "w88975.code-translate",
    "wakatime.vscode-wakatime",
    "wangtao0101.debug-leetcode",
    "wicked-labs.sequoia",
    "willasm.rc-script",
    "xaviercai.vscode-leetcode-cpp-debug",
    "yzane.markdown-pdf",
    "yzhang.markdown-all-in-one",
    "zhuangtongfa.material-theme"
)

$total = $extensions.Count
$failed = [System.Collections.ArrayList]::new()

Write-Host "共 $total 个扩展，开始安装（使用: $codeCmd）..." -ForegroundColor Cyan

for ($i = 0; $i -lt $total; $i++) {
    $id = $extensions[$i]
    $n = $i + 1
    Write-Host "[$n/$total] $id" -NoNewline
    try {
        & $codeCmd --install-extension $id 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            [void]$failed.Add($id)
            Write-Host " 失败" -ForegroundColor Red
        } else {
            Write-Host " 完成" -ForegroundColor Green
        }
    } catch {
        [void]$failed.Add($id)
        Write-Host " 失败: $_" -ForegroundColor Red
    }
}

if ($failed.Count -gt 0) {
    Write-Host "`n以下扩展安装失败 ($($failed.Count) 个):" -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Host "  - $_" }
} else {
    Write-Host "`n全部 $total 个扩展已安装完成。" -ForegroundColor Green
}
