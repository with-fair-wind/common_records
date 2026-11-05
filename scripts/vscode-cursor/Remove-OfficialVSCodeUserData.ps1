<#
.SYNOPSIS
在通过控制面板卸载官网版 VS Code 后，删除其默认用户数据。
.DESCRIPTION
默认预览；-Apply 才删除 APPDATA\Code、USERPROFILE\.vscode 和 .vscode-shared。
包含设置、扩展、状态、历史、备份、日志和缓存。不卸载程序或修改 PATH。
保护 Scoop 目录；检测到可能共享数据的 Scoop 或运行中的非便携实例时拒绝执行。
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OfficialVSCodeUserDataDirectory {
    if (-not $env:APPDATA -or -not $env:USERPROFILE) { throw 'APPDATA 或 USERPROFILE 未设置，无法确定默认用户数据目录。' }
    Join-Path $env:APPDATA 'Code'
    Join-Path $env:USERPROFILE '.vscode'
    Join-Path $env:USERPROFILE '.vscode-shared'
}

function Get-OfficialVSCodeExecutable {
    Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'
    foreach ($basePath in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | Select-Object -Unique) {
        Join-Path $basePath 'Microsoft VS Code\Code.exe'
    }
}

function Get-OfficialVSCodeScoopRoot {
    $roots = @($env:SCOOP, $env:SCOOP_GLOBAL, (Join-Path $env:USERPROFILE 'scoop'), (Join-Path $env:ProgramData 'scoop'))
    foreach ($command in Get-Command code -All -ErrorAction SilentlyContinue) {
        if ($command.Source -match '^(.*)[\\/]apps[\\/]vscode[\\/]current[\\/]bin[\\/]code(?:\.cmd)?$' -or
            $command.Source -match '^(.*)[\\/]shims[\\/]code(?:\.cmd|\.exe|\.ps1)?$') { $roots += $Matches[1] }
    }
    $roots | Where-Object { $_ } | Sort-Object -Unique
}

function Test-OfficialVSCodeChildPath {
    param([string]$Path, [string]$Parent)
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullParent = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    return $fullPath.Equals($fullParent, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-OfficialVSCodeUserDataPath {
    param([string]$Path, [string[]]$AllowedPaths)
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw "拒绝非绝对路径：$Path" }
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $allowed = @($AllowedPaths | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\', '/') })
    if ($fullPath -notin $allowed -or $fullPath -eq [IO.Path]::GetPathRoot($Path).TrimEnd('\', '/')) {
        throw "拒绝删除默认用户数据范围以外的路径：$Path"
    }
    foreach ($root in Get-OfficialVSCodeScoopRoot) {
        if (Test-OfficialVSCodeChildPath -Path $fullPath -Parent $root) { throw "拒绝删除 Scoop 目录：$Path" }
    }
    # 删除前校验绝对目标；拒绝目标或祖先通过 junction/symlink 重定向到其他目录。
    $ancestor = $fullPath
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "拒绝操作含符号链接或目录联接的路径：$ancestor" }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
}

function Assert-OfficialVSCodeUninstalled {
    foreach ($path in Get-OfficialVSCodeExecutable) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { throw "请先通过控制面板卸载官网版 VS Code，再删除用户数据：$path" }
    }
}

function Assert-OfficialVSCodeUserDataNotShared {
    param([string[]]$DataDirectories)
    foreach ($root in Get-OfficialVSCodeScoopRoot) {
        $installation = Join-Path $root 'apps\vscode\current'
        if (-not (Test-Path -LiteralPath $installation -PathType Container)) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $installation 'data') -PathType Container)) {
            throw "检测到非便携 Scoop VS Code，默认用户数据可能共用，停止删除：$installation"
        }
        if ($env:VSCODE_EXTENSIONS) {
            foreach ($directory in $DataDirectories) {
                if (Test-OfficialVSCodeChildPath -Path $env:VSCODE_EXTENSIONS -Parent $directory) {
                    throw "VSCODE_EXTENSIONS 指向待删除目录，可能被 Scoop 共用，停止删除：$env:VSCODE_EXTENSIONS"
                }
            }
        }
    }
}

function Assert-OfficialVSCodeUserDataNotInUse {
    foreach ($process in Get-Process -Name Code -ErrorAction SilentlyContinue) {
        $executablePath = $process.Path
        $portableScoop = $false
        if ($executablePath) {
            foreach ($root in Get-OfficialVSCodeScoopRoot) {
                if ((Test-OfficialVSCodeChildPath -Path $executablePath -Parent (Join-Path $root 'apps\vscode')) -and
                    (Test-Path -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($executablePath)) 'data') -PathType Container)) {
                    $portableScoop = $true
                    break
                }
            }
        }
        if (-not $portableScoop) { throw "请先关闭可能使用默认用户数据的 VS Code（进程 $($process.Id)），再清理。" }
    }
}

# 点导入只加载函数，供隔离测试使用。
if ($MyInvocation.InvocationName -eq '.') { return }
if (-not $IsWindows) { throw '此脚本仅支持 Windows。' }

$dataDirectories = @(Get-OfficialVSCodeUserDataDirectory)
$plan = @($dataDirectories | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
# 所有目标先检查，避免删除第一个目录后才发现另一个目录指向 Scoop。
foreach ($path in $plan) { Assert-OfficialVSCodeUserDataPath -Path $path -AllowedPaths $dataDirectories }
if ($plan.Count -eq 0) { Write-Host '未发现默认用户数据目录；没有进行修改。'; return }
Write-Host '待删除的默认用户数据（包括设置、扩展、历史、备份、日志和缓存）：'
$plan | ForEach-Object { Write-Host "  $_" }
if (-not $Apply -or $WhatIfPreference) {
    Write-Host '以上仅为预览。先通过控制面板卸载官网版，再添加 -Apply 执行删除；删除无法由脚本恢复。'
    return
}
Assert-OfficialVSCodeUninstalled
Assert-OfficialVSCodeUserDataNotShared -DataDirectories $dataDirectories
Assert-OfficialVSCodeUserDataNotInUse
$removed = 0
foreach ($path in $plan) {
    if ($PSCmdlet.ShouldProcess($path, '删除官网版 VS Code 默认用户数据')) {
        Assert-OfficialVSCodeUserDataNotShared -DataDirectories $dataDirectories
        Assert-OfficialVSCodeUserDataPath -Path $path -AllowedPaths $dataDirectories
        if (Test-Path -LiteralPath $path -PathType Container) {
            Remove-Item -LiteralPath $path -Recurse -Force
            $removed++
        }
    }
}
Write-Host "清理完成：删除 $removed 个默认用户数据目录，Scoop 数据未列入清理范围。" -ForegroundColor Green
