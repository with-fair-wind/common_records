#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([string]$ProjectPath = '.', [Parameter(Mandatory)][string]$BuildDirectory)
. "$PSScriptRoot\NvimCpp.Common.ps1"
$project = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $project 'CMakeLists.txt') -PathType Leaf)) { throw 'ProjectPath must be the CMake source root.' }
$build = if ([IO.Path]::IsPathRooted($BuildDirectory)) { $BuildDirectory } else { Join-Path $project $BuildDirectory }
$source = Join-Path $build 'compile_commands.json'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Database missing: $source. Configure Ninja with CMAKE_EXPORT_COMPILE_COMMANDS=ON first." }
$raw = Get-Content -LiteralPath $source -Raw
if (-not $raw.TrimStart().StartsWith('[')) { throw 'Compilation database must be a JSON array.' }
$entries = @($raw | ConvertFrom-Json -AsHashtable)
if ($entries.Count -eq 0) { throw 'Compilation database is empty.' }
foreach ($entry in $entries) {
    if ($entry -isnot [Collections.IDictionary] -or -not $entry['directory'] -or -not $entry['file'] -or
        (-not $entry['command'] -and -not $entry['arguments'])) { throw 'Invalid compilation database entry.' }
    if (-not (Test-Path -LiteralPath $entry['directory'] -PathType Container)) { throw "Compilation directory does not exist on this computer: $($entry['directory'])" }
}
$target = Join-Path $project 'compile_commands.json'
if (Test-Path -LiteralPath $target) {
    $item = Get-Item -LiteralPath $target -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Root database is a link. Manage the link explicitly.' }
    if ((Get-FileHash -LiteralPath $source).Hash -eq (Get-FileHash -LiteralPath $target).Hash) { Write-Host 'Compilation database already matches.'; return }
}
if ($PSCmdlet.ShouldProcess($target, "Copy compilation database from $source")) {
    Copy-Item -LiteralPath $source -Destination $target -Force
    Write-Host "Active database: $source ($($entries.Count) entries). Restart clangd if switching toolchain/preset."
}
