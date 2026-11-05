#Requires -Version 7.0
[CmdletBinding()]
param([string]$AppName = 'nvim-cpp', [switch]$RequireDeveloperEnvironment, [string]$SourceFile = '', [string]$BuildDirectory = '')
. "$PSScriptRoot\NvimCpp.Common.ps1"
$failed = [Collections.Generic.List[string]]::new()
foreach ($name in @('nvim', 'git', 'clangd', 'clang-format', 'clang-tidy', 'cmake', 'ctest', 'ninja', 'rg', 'fd', 'tree-sitter', 'python', 'curl.exe')) {
    $commands = @(Get-Command $name -CommandType Application -All -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) { $failed.Add("Missing: $name"); continue }
    Write-Host "$name -> $($commands[0].Source)"
    $output = & $commands[0].Source --version 2>&1
    if ($LASTEXITCODE -ne 0) { $failed.Add("Version check failed: $name"); continue }
    Write-Host ([string]($output | Select-Object -First 1))
    if ($name -eq 'nvim') {
        if (($output -join "`n") -notmatch 'NVIM v(\d+\.\d+\.\d+)' -or [version]$Matches[1] -lt [version]'0.11.2') { $failed.Add('Neovim >= 0.11.2 is required.') }
    }
    if ($commands.Count -gt 1) { Write-Warning "Multiple PATH candidates for ${name}: $($commands.Source -join ', ')" }
}
$config = Get-NvimCppConfigPath -AppName $AppName
Write-Host "Configuration: $config"
if (-not (Test-Path -LiteralPath (Join-Path $config 'init.lua'))) { $failed.Add('C++ configuration is not deployed.') }
if ($RequireDeveloperEnvironment) {
    foreach ($name in @('cl.exe', 'link.exe')) {
        if (-not (Get-Command $name -CommandType Application -ErrorAction SilentlyContinue)) { $failed.Add("Developer tool missing: $name") }
    }
    if (-not $env:INCLUDE -or -not $env:LIB) { $failed.Add('Developer INCLUDE/LIB missing.') }
}
if ($SourceFile) {
    if (-not $BuildDirectory) { throw '-SourceFile requires -BuildDirectory to select an explicit database.' }
    $source = (Resolve-Path -LiteralPath $SourceFile).Path
    $build = (Resolve-Path -LiteralPath $BuildDirectory).Path
    if (-not (Test-Path -LiteralPath (Join-Path $build 'compile_commands.json'))) { throw 'BuildDirectory has no compile_commands.json.' }
    Invoke-NvimCppNative -Command 'clangd' -Arguments @("--check=$source", "--compile-commands-dir=$build", '--log=verbose')
}
if ($failed.Count -gt 0) { throw ($failed -join "`n") }
Write-Host 'Environment checks passed. Run :LazyHealth and :checkhealth vim.lsp inside Neovim next.'
