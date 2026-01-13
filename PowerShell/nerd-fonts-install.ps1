<#
.SYNOPSIS
批量安装常用 Nerd Fonts（通过 Scoop 的 nerd-fonts bucket）。

.DESCRIPTION
默认安装一组常用 Nerd Fonts；会自动检查 Scoop 是否存在、确保 nerd-fonts bucket 已添加，
并默认跳过已安装字体（可选对已安装字体执行升级）。

.PARAMETER Fonts
要安装的字体清单（manifest 名称，不含 bucket 前缀）。不传则使用脚本内置的常用列表。

.PARAMETER Upgrade
如果字体已安装，则执行 `scoop update <font>` 进行升级。

.PARAMETER UpdateScoop
在安装前先执行一次 `scoop update`（更新 Scoop 自身与 buckets）。

.PARAMETER NoBucketAdd
不自动添加 nerd-fonts bucket（仅当你已手动添加时使用）。

.PARAMETER List
仅输出脚本内置的“常用字体列表”，不执行安装。

.EXAMPLE
.\nerd-fonts-install.ps1

.EXAMPLE
.\nerd-fonts-install.ps1 -Fonts meslo-lg-nf-mono,jetbrainsmono-nf-mono

.EXAMPLE
.\nerd-fonts-install.ps1 -Upgrade

.EXAMPLE
.\nerd-fonts-install.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string[]]$Fonts,
    [switch]$Upgrade,
    [switch]$UpdateScoop,
    [switch]$NoBucketAdd,
    [switch]$List
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-ScoopPresent {
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        throw "未找到 'scoop' 命令。请先安装 Scoop（见 https://scoop.sh/ ），再运行此脚本。"
    }
}

function Invoke-Scoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias('Args')]
        [string[]]$ScoopArgs,

        [int[]]$AllowedExitCodes = @(0)
    )

    # 注意：当脚本以 -WhatIf 运行时，$WhatIfPreference=$true 可能会影响 scoop 内部调用的
    # 支持 ShouldProcess 的 cmdlet（例如 Update-FormatData），导致输出/行为异常。
    # 这里对 scoop 调用临时禁用 WhatIf，保证只读命令（list/bucket list）也能稳定工作。
    $prevWhatIf = $WhatIfPreference
    try {
        $WhatIfPreference = $false
        $output = & scoop @ScoopArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $WhatIfPreference = $prevWhatIf
    }

    if ($exitCode -ne 0) {
        $msg = ($output | Out-String).TrimEnd()
        if ($AllowedExitCodes -notcontains $exitCode) {
            throw "执行失败：scoop $($ScoopArgs -join ' ') (exit $exitCode)`n$msg"
        }
    }

    return $output
}

function Get-ScoopBuckets {
    $lines = Invoke-Scoop -Args @('bucket', 'list')
    foreach ($line in $lines) {
        # scoop bucket list 通常返回对象（Name/Source/Updated...）
        $nameProp = $line.PSObject.Properties['Name']
        if ($null -ne $nameProp) {
            $name = ([string]$nameProp.Value).Trim()
            if ($name) { $name }
            continue
        }

        $t = ([string]$line).Trim()
        if (-not $t) { continue }
        if ($t -match '^(Name\s+Source|---+)') { continue }
        if ($t -match '^(?<name>\S+)') { $Matches['name'] }
    }
}

function Get-ScoopInstalledApps {
    $lines = Invoke-Scoop -Args @('list')
    foreach ($line in $lines) {
        # scoop list 通常返回对象（Name/Version/Source/Updated...）
        $nameProp = $line.PSObject.Properties['Name']
        if ($null -ne $nameProp) {
            $name = ([string]$nameProp.Value).Trim()
            if ($name) { $name }
            continue
        }

        $t = ([string]$line).Trim()
        if (-not $t) { continue }
        if ($t -match '^Installed apps:\s*$') { continue }
        if ($t -match '^(Name\s+Version|---+)') { continue }
        if ($t -match '^(?<name>\S+)') {
            $name = $Matches['name']
            if ($name -eq 'Name') { continue }
            $name
        }
    }
}

# 常用 Nerd Fonts 字体列表（可通过 -Fonts 覆盖）
$defaultFonts = @(
    "cascadiacode-nf-mono",     # Cascadia Code Nerd Font Mono
    "jetbrainsmono-nf-mono",    # JetBrains Mono Nerd Font Mono
    "firacode-nf-mono",         # Fira Code Nerd Font Mono
    "hack-nf-mono",             # Hack Nerd Font Mono
    "iosevka-nf-mono",          # Iosevka Nerd Font Mono
    "dejavusansmono-nf-mono",   # DejaVu Sans Mono Nerd Font Mono
    "sourcecodepro-nf-mono",    # Source Code Pro Nerd Font Mono
    "ubuntu-nf-mono"            # Ubuntu Nerd Font Mono
)

if ($List) {
    $defaultFonts
    return
}

if (-not $Fonts -or $Fonts.Count -eq 0) {
    $Fonts = $defaultFonts
}

# 去重、去空白
$Fonts = $Fonts |
ForEach-Object { ([string]$_).Trim() } |
Where-Object { $_ } |
Sort-Object -Unique

Assert-ScoopPresent

if ($UpdateScoop) {
    if ($PSCmdlet.ShouldProcess("Scoop", "scoop update（更新 Scoop 与 buckets）")) {
        Write-Host "Updating Scoop and buckets..." -ForegroundColor Cyan
        Invoke-Scoop -Args @('update') | Out-Host
    }
}

if (-not $NoBucketAdd) {
    $buckets = @(Get-ScoopBuckets)
    if ($buckets -notcontains 'nerd-fonts') {
        if ($PSCmdlet.ShouldProcess("nerd-fonts bucket", "scoop bucket add nerd-fonts")) {
            Write-Host "Adding bucket: nerd-fonts ..." -ForegroundColor Cyan
            # 某些版本的 scoop 在 bucket 已存在时会返回 exit 2（并给出 WARN），这里视为可接受。
            Invoke-Scoop -Args @('bucket', 'add', 'nerd-fonts') -AllowedExitCodes @(0, 2) | Out-Host
        }
    }
}

$installed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($name in (Get-ScoopInstalledApps)) { [void]$installed.Add($name) }

$total = $Fonts.Count
$ok = 0
$skipped = 0
$failed = New-Object System.Collections.Generic.List[string]
$planInstall = 0
$planUpgrade = 0
$planSkip = 0

for ($i = 0; $i -lt $total; $i++) {
    $font = $Fonts[$i]
    $percent = [int](($i + 1) / [double]$total * 100)
    Write-Progress -Activity "Nerd Fonts 安装中" -Status "$font ($($i + 1)/$total)" -PercentComplete $percent

    try {
        if ($installed.Contains($font)) {
            if ($Upgrade) {
                $planUpgrade++
                if ($PSCmdlet.ShouldProcess($font, "scoop update $font（升级已安装字体）")) {
                    Write-Host "Upgrading: $font ..." -ForegroundColor Yellow
                    Invoke-Scoop -Args @('update', $font) | Out-Host
                    $ok++
                }
            }
            else {
                $planSkip++
                Write-Host "已安装，跳过: $font" -ForegroundColor DarkGray
                $skipped++
            }
            continue
        }

        $planInstall++
        $fullName = "nerd-fonts/$font"
        if ($PSCmdlet.ShouldProcess($fullName, "scoop install $fullName（安装字体）")) {
            Write-Host "Installing: $font ..." -ForegroundColor Cyan
            Invoke-Scoop -Args @('install', $fullName) | Out-Host
            $ok++
        }
    }
    catch {
        $failed.Add($font) | Out-Null
        Write-Host "失败: $font`n$($_.Exception.Message)" -ForegroundColor Red
        continue
    }
}

Write-Progress -Activity "Nerd Fonts 安装中" -Completed

Write-Host ""
if ($WhatIfPreference) {
    Write-Host "WhatIf 模式：未实际执行安装/升级。计划：安装 $planInstall，升级 $planUpgrade，跳过 $planSkip。" -ForegroundColor Yellow
}
else {
    Write-Host "完成：成功 $ok，跳过 $skipped，失败 $($failed.Count)。" -ForegroundColor Green
}
if ($failed.Count -gt 0) {
    Write-Host "失败列表：" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    throw "有 $($failed.Count) 个字体安装/升级失败：$($failed -join ', ')"
}
