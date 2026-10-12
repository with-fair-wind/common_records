# Tests execute only the process-check sections, never the update/install body.
BeforeAll {
    $sourcePath = Join-Path $PSScriptRoot '..\Update-ScoopOfflineBundle.ps1'
    $source = Get-Content -LiteralPath $sourcePath -Raw
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
    if ($errors) { throw ($errors -join "`n") }
    $helper = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-PackageNameFromSpec' }, $true)
    . ([scriptblock]::Create($helper.Extent.Text))
    $start = $source.IndexOf('# 集中维护：')
    $end = $source.IndexOf('# 先补齐 / 校验本地 cache。', $start)
    if ($start -lt 0 -or $end -lt 0) { throw 'Preflight section missing.' }
    $script:preflight = [scriptblock]::Create($source.Substring($start, $end - $start))
    $start = $source.IndexOf('        # 预检到此处已过 cache 拷贝耗时')
    $end = $source.IndexOf('        # 不传 scoop；', $start)
    if ($start -lt 0 -or $end -lt 0) { throw 'Final process-check section missing.' }
    $script:finalCheck = [scriptblock]::Create($source.Substring($start, $end - $start))

    function Invoke-Preflight {
        param([string[]]$Specs, [switch]$SkipAppUpdate, [switch]$StopRunningProcesses)
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $ScoopRoot = Join-Path ([IO.Path]::GetTempPath()) 'scoop-process-fixture'
        $metadata = [PSCustomObject]@{ DownloadedPackages = @($Specs | ForEach-Object { [PSCustomObject]@{ Spec = $_ } }) }
        . $script:preflight
        $pendingProcessNames
    }
}

Describe 'Offline bundle application process checks' {
    BeforeEach {
        $script:runningName = ''
        $script:isInstalled = $true
        Mock Test-Path { return $script:isInstalled }
        Mock Get-Process {
            if ($Name -eq $script:runningName) {
                [PSCustomObject]@{ Id = 123; ProcessName = $Name }
            }
        }
        Mock Stop-Process {}
        Mock Start-Sleep {}
    }

    It 'Does not inspect or stop applications with SkipAppUpdate' {
        $script:runningName = 'Code'
        @(Invoke-Preflight -Specs 'extras/vscode' -SkipAppUpdate -StopRunningProcesses).Count | Should -Be 0
        Should -Invoke Get-Process -Times 0 -Exactly
        Should -Invoke Stop-Process -Times 0 -Exactly
    }

    It 'Ignores applications not installed on the target' {
        $script:isInstalled = $false
        @(Invoke-Preflight -Specs 'extras/vscode').Count | Should -Be 0
        Should -Invoke Get-Process -Times 0 -Exactly
    }

    It 'Ignores unrelated applications when only a CLI package is in the bundle' {
        $script:runningName = 'Code'
        @(Invoke-Preflight -Specs 'cmake').Count | Should -Be 0
        Should -Invoke Get-Process -Times 0 -Exactly
    }

    It 'Handles one pending application with no running process under StrictMode' {
        @(Invoke-Preflight -Specs 'extras/vscode') | Should -Be @('Code')
        Should -Invoke Get-Process -Times 1 -Exactly -ParameterFilter { $Name -eq 'Code' }
    }

    It 'Blocks a running target application before replacing deployed files' {
        $script:runningName = 'Code'
        { Invoke-Preflight -Specs 'extras/vscode' } | Should -Throw '*独立 PowerShell*'
        Should -Invoke Stop-Process -Times 0 -Exactly
    }

    It 'Stops a running target only when explicitly requested' {
        $script:runningName = 'Code'
        Invoke-Preflight -Specs 'extras/vscode' -StopRunningProcesses | Should -Be 'Code'
        Should -Invoke Stop-Process -Times 1 -Exactly
    }

    It 'Checks the actual Terminal Preview executable process and deduplicates variants' {
        $script:runningName = 'WindowsTerminal'
        { Invoke-Preflight -Specs @('extras/windows-terminal', 'versions/windows-terminal-preview') } | Should -Throw '*WindowsTerminal*'
        Should -Invoke Get-Process -Times 1 -Exactly -ParameterFilter { $Name -eq 'WindowsTerminal' }
    }

    It 'Blocks an application restarted after preflight even with StopRunningProcesses enabled' {
        $script:runningName = 'WindowsTerminal'
        $appsToUpdate = @('versions/windows-terminal-preview')
        $PackageProcessMap = @{ 'windows-terminal-preview' = @('WindowsTerminal') }
        $StopRunningProcesses = $true
        { . $script:finalCheck } | Should -Throw '*scoop update 前*'
        Should -Invoke Stop-Process -Times 0 -Exactly
    }

    It 'Allows the final check when no target application is running' {
        $appsToUpdate = @('extras/vscode')
        $PackageProcessMap = @{ 'vscode' = @('Code') }
        { . $script:finalCheck } | Should -Not -Throw
        Should -Invoke Stop-Process -Times 0 -Exactly
    }
}
