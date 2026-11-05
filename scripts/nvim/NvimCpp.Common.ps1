#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NvimCppNative {
    param([Parameter(Mandatory)][string]$Command, [string[]]$Arguments = @())
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed (exit $LASTEXITCODE)." }
}

function Get-NvimCppConfigPath {
    param([string]$AppName = 'nvim-cpp')
    if ($AppName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') {
        throw 'AppName must be a single directory name (letters, digits, underscore, hyphen).'
    }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is missing. Windows is required.' }
    $base = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { $env:LOCALAPPDATA }
    return [IO.Path]::GetFullPath((Join-Path $base $AppName))
}

function Get-NvimCppVsPath {
    param([string]$VsPath = '')
    if ($VsPath) { return (Resolve-Path -LiteralPath $VsPath).Path }
    $locator = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $locator -PathType Leaf)) {
        throw 'vswhere.exe not found. Install Visual Studio / Build Tools with Desktop development with C++, or specify -VsPath.'
    }
    $found = & $locator -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $found) { throw 'No Visual Studio installation with the x86/x64 C++ tools was found.' }
    return ([string]($found | Select-Object -First 1)).Trim()
}

function Enter-NvimCppDeveloperEnvironment {
    param([string]$VsPath = '', [ValidateSet('x64', 'x86')][string]$Arch = 'x64')
    $installation = Get-NvimCppVsPath -VsPath $VsPath
    $module = Join-Path $installation 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) { throw "Developer PowerShell module not found: $module" }
    Import-Module -Name $module
    Enter-VsDevShell -VsInstallPath $installation -SkipAutomaticLocation -DevCmdArguments "-arch=$Arch -host_arch=x64" | Out-Null
    foreach ($name in @('cl.exe', 'link.exe')) {
        if (-not (Get-Command $name -CommandType Application -ErrorAction SilentlyContinue)) { throw "$name is missing after VS initialization." }
    }
    if (-not $env:INCLUDE -or -not $env:LIB) { throw 'Visual Studio INCLUDE/LIB environment is incomplete.' }
    Write-Host "Visual Studio: $installation ($Arch)"
}
