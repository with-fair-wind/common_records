#Requires -Version 7.0
<#
.SYNOPSIS
Deploy an isolated LazyVim C++ configuration on Windows.
.DESCRIPTION
Tools are installed only with -InstallTools. Updates require -Update and keep a
backup. Local overrides and lazy-lock.json survive unless -LockFile is supplied.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$AppName = 'nvim-cpp',
    [switch]$InstallTools,
    [switch]$Update,
    [string]$LockFile = ''
)
. "$PSScriptRoot\NvimCpp.Common.ps1"
$destination = Get-NvimCppConfigPath -AppName $AppName
$source = Join-Path $PSScriptRoot 'config'
if ($LockFile) {
    $LockFile = (Resolve-Path -LiteralPath $LockFile).Path
    $lock = Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json -AsHashtable
    if ($lock -isnot [Collections.IDictionary] -or $lock.Count -eq 0) { throw 'LockFile must be a non-empty lazy-lock.json object.' }
    foreach ($entry in $lock.Values) {
        if ($entry -isnot [Collections.IDictionary] -or [string]$entry['commit'] -notmatch '^[0-9a-fA-F]{40}$') {
            throw 'Every lock entry must contain a full 40-character Git commit.'
        }
    }
}
$files = @(Get-ChildItem -LiteralPath $source -File -Recurse)
$changed = @($files | Where-Object {
    $relative = [IO.Path]::GetRelativePath($source, $_.FullName)
    $target = Join-Path $destination $relative
    -not (Test-Path -LiteralPath $target -PathType Leaf) -or
        (Get-FileHash -LiteralPath $_.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash
})
if ((Test-Path -LiteralPath $destination) -and $changed.Count -gt 0 -and -not $Update) {
    throw "Configuration already exists: $destination. Review changes and use -Update to back it up and deploy."
}
if ($InstallTools) {
    $packages = [ordered]@{
        git = @('git.exe'); neovim = @('nvim.exe'); ripgrep = @('rg.exe')
        fd = @('fd.exe'); lazygit = @('lazygit.exe'); llvm = @('clangd.exe', 'clang-format.exe', 'clang-tidy.exe', 'clang-cl.exe')
        python = @('python.exe'); cmake = @('cmake.exe', 'ctest.exe'); ninja = @('ninja.exe'); 'tree-sitter' = @('tree-sitter.exe')
    }
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        throw 'Scoop is required for -InstallTools. Install it first, or deploy with preinstalled tools without this switch.'
    }
    foreach ($package in $packages.Keys) {
        $missing = @($packages[$package] | Where-Object { -not (Get-Command $_ -CommandType Application -ErrorAction SilentlyContinue) })
        if ($missing.Count -eq 0) { Write-Host "Using installed tool(s): $package"; continue }
        if ($PSCmdlet.ShouldProcess($package, 'Install missing tools using Scoop')) {
            Invoke-NvimCppNative -Command 'scoop' -Arguments @('install', $package)
            foreach ($exe in $packages[$package]) {
                if (-not (Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue)) { throw "$exe still missing. Check PATH / Scoop installation." }
            }
        }
    }
}
$lockTarget = Join-Path $destination 'lazy-lock.json'
$lockChanged = $LockFile -and (-not (Test-Path -LiteralPath $lockTarget) -or
    (Get-FileHash -LiteralPath $LockFile).Hash -ne (Get-FileHash -LiteralPath $lockTarget).Hash)
if ($changed.Count -gt 0 -or $lockChanged) {
    if ($PSCmdlet.ShouldProcess($destination, 'Back up existing configuration and deploy C++ configuration')) {
        if (Test-Path -LiteralPath $destination) {
            $backup = "$destination.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N').Substring(0,8))"
            Copy-Item -LiteralPath $destination -Destination $backup -Recurse -Force
            Write-Host "Backup: $backup"
        }
        foreach ($file in $changed) {
            $relative = [IO.Path]::GetRelativePath($source, $file.FullName)
            $target = Join-Path $destination $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        }
        if ($lockChanged) { Copy-Item -LiteralPath $LockFile -Destination $lockTarget -Force }
    }
} else { Write-Host 'Configuration already matches; no files changed.' }
Write-Host "Configuration: $destination"
Write-Host 'Launch with Start-NvimCpp.ps1. First launch downloads plugins.'
