#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ProjectPath = '.',
    [string]$AppName = 'nvim-cpp',
    [string]$VsPath = '',
    [ValidateSet('x64', 'x86')][string]$Arch = 'x64',
    [switch]$SkipDeveloperEnvironment,
    [switch]$EnvironmentOnly,
    [string[]]$NvimArguments = @('.')
)
. "$PSScriptRoot\NvimCpp.Common.ps1"
$configPath = Get-NvimCppConfigPath -AppName $AppName
if (-not $EnvironmentOnly -and -not (Test-Path -LiteralPath (Join-Path $configPath 'init.lua'))) { throw "Configuration missing: $configPath. Run Install-NvimCpp.ps1 first." }
$project = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not (Test-Path -LiteralPath $project -PathType Container)) { throw 'ProjectPath must be a directory.' }
if (-not $SkipDeveloperEnvironment) { Enter-NvimCppDeveloperEnvironment -VsPath $VsPath -Arch $Arch }
if ($EnvironmentOnly) { Write-Host 'Developer environment initialized in this PowerShell process.'; return }
$previousApp = $env:NVIM_APPNAME
Push-Location -LiteralPath $project
try {
    $env:NVIM_APPNAME = $AppName
    Invoke-NvimCppNative -Command 'nvim' -Arguments $NvimArguments
} finally {
    $env:NVIM_APPNAME = $previousApp
    Pop-Location
}
