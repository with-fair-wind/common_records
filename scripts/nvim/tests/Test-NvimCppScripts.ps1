#Requires -Version 7.0
# Filesystem regression tests; no network, Scoop install, or real user config writes.
[CmdletBinding()]
param()
. "$PSScriptRoot\..\NvimCpp.Common.ps1"
function Assert-True { param([bool]$Value, [string]$Message); if (-not $Value) { throw $Message } }
function Assert-Throws { param([scriptblock]$Action); $thrown = $false; try { & $Action } catch { $thrown = $true }; Assert-True $thrown 'Expected failure did not occur.' }
$workParent = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.work'))
$work = Join-Path $workParent ([guid]::NewGuid().ToString('N'))
$previousXdg = $env:XDG_CONFIG_HOME
try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $env:XDG_CONFIG_HOME = $work
    $install = Join-Path $PSScriptRoot '..\Install-NvimCpp.ps1'
    $config = Join-Path $work 'nvim-cpp'
    & $install -WhatIf
    Assert-True (-not (Test-Path -LiteralPath $config)) 'WhatIf wrote configuration.'
    Assert-Throws { & $install -AppName '../nvim' }
    & $install
    $init = Join-Path $config 'init.lua'
    $first = (Get-Item -LiteralPath $init).LastWriteTimeUtc
    & $install
    Assert-True ((Get-Item -LiteralPath $init).LastWriteTimeUtc -eq $first) 'Idempotent install rewrote the file.'
    $local = Join-Path $config 'lua\config\local.lua'
    Set-Content -LiteralPath $local -Value 'return { clang_tidy = true }'
    $lock = Join-Path $config 'lazy-lock.json'
    Set-Content -LiteralPath $lock -Value '{"LazyVim":{"branch":"main","commit":"example"}}'
    Set-Content -LiteralPath $init -Value '-- customized'
    Assert-Throws { & $install }
    Assert-True ((Get-Content -LiteralPath $init -Raw).Trim() -eq '-- customized') 'Refused update changed config.'
    & $install -Update
    Assert-True ((Get-Content -LiteralPath $local -Raw).Contains('true')) 'Update lost local override.'
    Assert-True ((Get-Content -LiteralPath $lock -Raw).Contains('example')) 'Update lost lock.'
    $backups = @(Get-ChildItem -LiteralPath $work -Directory -Filter 'nvim-cpp.backup-*')
    Assert-True ($backups.Count -eq 1) 'Update should create one backup.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'init.lua') -Raw).Contains('customized')) 'Backup lost old content.'
    $otherLock = Join-Path $work 'shared-lock.json'
    Set-Content -LiteralPath $otherLock -Value '{"shared":{"branch":"main","commit":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}'
    & $install -LockFile $otherLock
    Assert-True ((Get-Content -LiteralPath $lock -Raw).Contains('shared')) 'Explicit lock was not deployed.'
    Assert-Throws { Invoke-NvimCppNative -Command 'pwsh' -Arguments @('-NoProfile', '-Command', 'exit 9') }
    $project = Join-Path $work 'C++ 项目 with spaces'
    $build = Join-Path $project 'build debug'
    New-Item -ItemType Directory -Path $build -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project 'CMakeLists.txt') -Value 'project(Fixture)'
    $database = Join-Path $build 'compile_commands.json'
    $rootDatabase = Join-Path $project 'compile_commands.json'
    $entry = @{ directory = $build; file = 'main.cpp'; arguments = @('cl.exe', '/c', 'main.cpp') }
    ConvertTo-Json -InputObject @($entry) -Depth 5 | Set-Content -LiteralPath $database
    $sync = Join-Path $PSScriptRoot '..\Update-NvimCppDatabase.ps1'
    & $sync -ProjectPath $project -BuildDirectory 'build debug' -WhatIf
    Assert-True (-not (Test-Path -LiteralPath $rootDatabase)) 'Database WhatIf wrote files.'
    & $sync -ProjectPath $project -BuildDirectory 'build debug'
    Assert-True ((Get-FileHash -LiteralPath $database).Hash -eq (Get-FileHash -LiteralPath $rootDatabase).Hash) 'Database sync corrupted content.'
    & $sync -ProjectPath $project -BuildDirectory 'build debug'
    $before = (Get-FileHash -LiteralPath $rootDatabase).Hash
    Set-Content -LiteralPath $database -Value '[]'
    Assert-Throws { & $sync -ProjectPath $project -BuildDirectory 'build debug' }
    Set-Content -LiteralPath $database -Value '[{"directory":"Z:/not-a-local-path","file":"main.cpp","command":"cl /c main.cpp"}]'
    Assert-Throws { & $sync -ProjectPath $project -BuildDirectory 'build debug' }
    Assert-True ((Get-FileHash -LiteralPath $rootDatabase).Hash -eq $before) 'Invalid database overwrote active database.'
    Write-Host 'Deployment and database regression tests passed.'
} finally {
    $env:XDG_CONFIG_HOME = $previousXdg
    # Only delete this test's GUID directory after checking the resolved boundary.
    $resolved = [IO.Path]::GetFullPath($work)
    if ($resolved.StartsWith($workParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
