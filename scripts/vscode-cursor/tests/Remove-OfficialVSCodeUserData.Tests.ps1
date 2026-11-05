#Requires -Version 7.0
BeforeAll {
    $script:cleanupScript = Join-Path $PSScriptRoot '../Remove-OfficialVSCodeUserData.ps1'
    . $script:cleanupScript
    $source = Get-Content -LiteralPath $script:cleanupScript -Raw
    $start = $source.LastIndexOf('$dataDirectories = @(Get-OfficialVSCodeUserDataDirectory)', [StringComparison]::Ordinal)
    if ($start -lt 0) { throw 'User data cleanup entry point missing.' }
    $script:cleanupMain = [scriptblock]::Create($source.Substring($start))
    function Invoke-TestUserDataCleanup {
        [CmdletBinding(SupportsShouldProcess)]
        param([switch]$Apply)
        . $script:cleanupMain
    }
}

Describe 'Official VS Code full user data cleanup after uninstall' {
    BeforeEach {
        $script:fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:dataDirectories = @((Join-Path $script:fixture 'AppData/Roaming/Code'), (Join-Path $script:fixture '.vscode'), (Join-Path $script:fixture '.vscode-shared'))
        $script:scoopRoot = Join-Path $script:fixture 'scoop'
        $script:scoopInstallation = Join-Path $script:scoopRoot 'apps/vscode/current'
        $script:officialExe = Join-Path $script:fixture 'official/Code.exe'
        $script:project = Join-Path $script:fixture 'projects/demo/.vscode'
        foreach ($directory in $script:dataDirectories) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'fixture.txt') 'user data'
        }
        foreach ($name in @('User/History', 'User/globalStorage', 'Cache', 'logs', 'Backups')) {
            New-Item -ItemType Directory -Path (Join-Path $script:dataDirectories[0] $name) -Force | Out-Null
        }
        New-Item -ItemType Directory -Path (Join-Path $script:scoopInstallation 'data/user-data'), $script:project -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:project 'settings.json') '{}'
        $script:oldExtensionsEnv = $env:VSCODE_EXTENSIONS
        $env:VSCODE_EXTENSIONS = $null
        Mock Get-OfficialVSCodeUserDataDirectory { $script:dataDirectories }
        Mock Get-OfficialVSCodeExecutable { $script:officialExe }
        Mock Get-OfficialVSCodeScoopRoot { $script:scoopRoot }
        Mock Get-Process {}
        Mock Start-Process { throw 'User data cleanup must not launch an uninstaller' }
    }

    AfterEach { $env:VSCODE_EXTENSIONS = $script:oldExtensionsEnv }

    It 'Only previews by default' {
        Invoke-TestUserDataCleanup
        foreach ($directory in $script:dataDirectories) { Test-Path -LiteralPath (Join-Path $directory 'fixture.txt') | Should -BeTrue }
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'WhatIf overrides Apply' {
        Invoke-TestUserDataCleanup -Apply -WhatIf
        foreach ($directory in $script:dataDirectories) { Test-Path -LiteralPath $directory | Should -BeTrue }
    }

    It 'Removes all three default data directories while preserving portable Scoop and project settings' {
        Invoke-TestUserDataCleanup -Apply
        foreach ($directory in $script:dataDirectories) { Test-Path -LiteralPath $directory | Should -BeFalse }
        Test-Path -LiteralPath (Join-Path $script:scoopInstallation 'data/user-data') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:project 'settings.json') | Should -BeTrue
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'Can be repeated after all default data has been removed' {
        Invoke-TestUserDataCleanup -Apply
        { Invoke-TestUserDataCleanup -Apply } | Should -Not -Throw
    }

    It 'Requires control panel uninstall before deleting any data' {
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($script:officialExe)) -Force | Out-Null
        Set-Content -LiteralPath $script:officialExe 'fixture executable'
        { Invoke-TestUserDataCleanup -Apply } | Should -Throw '*请先通过控制面板卸载*'
        foreach ($directory in $script:dataDirectories) { Test-Path -LiteralPath $directory | Should -BeTrue }
        Test-Path -LiteralPath $script:officialExe | Should -BeTrue
    }

    It 'Refuses deletion when a non-portable Scoop installation may share data' {
        $script:otherScoopRoot = Join-Path $script:fixture 'nonportable-scoop'
        New-Item -ItemType Directory -Path (Join-Path $script:otherScoopRoot 'apps/vscode/current') -Force | Out-Null
        Mock Get-OfficialVSCodeScoopRoot { $script:otherScoopRoot }
        { Invoke-TestUserDataCleanup -Apply } | Should -Throw '*默认用户数据可能共用*'
        foreach ($directory in $script:dataDirectories) { Test-Path -LiteralPath $directory | Should -BeTrue }
    }

    It 'Refuses an extension-directory override pointing into data that would be removed' {
        $env:VSCODE_EXTENSIONS = Join-Path $script:dataDirectories[1] 'extensions'
        { Invoke-TestUserDataCleanup -Apply } | Should -Throw '*VSCODE_EXTENSIONS*'
        foreach ($directory in $script:dataDirectories) { Test-Path -LiteralPath $directory | Should -BeTrue }
    }

    It 'Requires closing Code processes that might still use default data' {
        Mock Get-Process { [pscustomobject]@{Id=123; Path='C:\custom\Code.exe'} }
        { Invoke-TestUserDataCleanup -Apply } | Should -Throw '*请先关闭*'
        foreach ($directory in $script:dataDirectories) { Test-Path -LiteralPath $directory | Should -BeTrue }
    }

    It 'Allows a separately stored portable Scoop process to continue running' {
        Mock Get-Process { [pscustomobject]@{Id=456; Path=(Join-Path $script:scoopInstallation 'Code.exe')} }
        Invoke-TestUserDataCleanup -Apply
        Test-Path -LiteralPath (Join-Path $script:scoopInstallation 'data') | Should -BeTrue
    }

    It 'Rejects parent directories and lookalike siblings' {
        foreach ($path in @($script:fixture, ($script:dataDirectories[1] + '-other'))) {
            { Assert-OfficialVSCodeUserDataPath -Path $path -AllowedPaths $script:dataDirectories } | Should -Throw '*范围以外*'
        }
    }

    It 'Rejects a Scoop directory even if it was added to the allowed paths' {
        $path = Join-Path $script:scoopInstallation 'data'
        { Assert-OfficialVSCodeUserDataPath -Path $path -AllowedPaths @($path) } | Should -Throw '*Scoop 目录*'
    }

    It 'Rejects a redirected data directory before deleting the other directories' {
        $junction = Join-Path $script:fixture 'redirected-data'
        New-Item -ItemType Junction -Path $junction -Target (Join-Path $script:scoopInstallation 'data') | Out-Null
        $script:dataDirectories[2] = $junction
        try {
            { Invoke-TestUserDataCleanup -Apply } | Should -Throw '*目录联接*'
            Test-Path -LiteralPath $script:dataDirectories[0] | Should -BeTrue
            Test-Path -LiteralPath $script:dataDirectories[1] | Should -BeTrue
        }
        finally { Remove-Item -LiteralPath $junction -Force }
        Test-Path -LiteralPath (Join-Path $script:scoopInstallation 'data') | Should -BeTrue
    }
}
