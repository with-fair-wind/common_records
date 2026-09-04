#Requires -Version 7.0

BeforeAll {
    $scriptUnderTest = (Resolve-Path (Join-Path $PSScriptRoot "..\git_recursive_checkout_pull.ps1")).Path

    function Invoke-TestGit {
        param(
            [Parameter(Mandatory)][string]$Repository,
            [Parameter(Mandatory)][string[]]$ArgumentList
        )

        $output = & git -C $Repository @ArgumentList 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "git -C $Repository $($ArgumentList -join ' ') failed: $(($output | Out-String).Trim())"
        }
    }

    function Invoke-TestGitGlobal {
        param([Parameter(Mandatory)][string[]]$ArgumentList)

        $output = & git @ArgumentList 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "git $($ArgumentList -join ' ') failed: $(($output | Out-String).Trim())"
        }
    }

    function Invoke-TestFixtureSetup {
        param(
            [Parameter(Mandatory)][string]$Root,
            [string]$SubmoduleBranch = "release",
            [ValidateRange(1, 2)][int]$ChildCount = 1
        )

        $remoteRoot = Join-Path $Root "remotes"
        $childRemote = Join-Path $remoteRoot "child.git"
        $mainRemote = Join-Path $remoteRoot "main.git"
        $childWork = Join-Path $Root "child-source"
        $mainWork = Join-Path $Root "main"
        New-Item -ItemType Directory -Path $remoteRoot, $childWork, $mainWork -Force | Out-Null

        Invoke-TestGitGlobal -ArgumentList @("init", "--bare", $childRemote)
        Invoke-TestGitGlobal -ArgumentList @("init", "--bare", $mainRemote)

        Invoke-TestGitGlobal -ArgumentList @("init", "--initial-branch=developbim", $childWork)
        Invoke-TestGit -Repository $childWork -ArgumentList @("config", "user.name", "Codex Test")
        Invoke-TestGit -Repository $childWork -ArgumentList @("config", "user.email", "codex@example.invalid")
        Set-Content -LiteralPath (Join-Path $childWork "README.md") -Value "child fixture" -Encoding utf8NoBOM
        Invoke-TestGit -Repository $childWork -ArgumentList @("add", "README.md")
        Invoke-TestGit -Repository $childWork -ArgumentList @("commit", "-m", "initial child")
        Invoke-TestGit -Repository $childWork -ArgumentList @("branch", "release")
        Invoke-TestGit -Repository $childWork -ArgumentList @("remote", "add", "origin", $childRemote)
        Invoke-TestGit -Repository $childWork -ArgumentList @("push", "-u", "origin", "developbim")
        Invoke-TestGit -Repository $childWork -ArgumentList @("push", "origin", "release")

        Invoke-TestGitGlobal -ArgumentList @("init", "--initial-branch=developbim", $mainWork)
        Invoke-TestGit -Repository $mainWork -ArgumentList @("config", "user.name", "Codex Test")
        Invoke-TestGit -Repository $mainWork -ArgumentList @("config", "user.email", "codex@example.invalid")
        Set-Content -LiteralPath (Join-Path $mainWork "README.md") -Value "main fixture" -Encoding utf8NoBOM
        Invoke-TestGit -Repository $mainWork -ArgumentList @("add", "README.md")
        Invoke-TestGit -Repository $mainWork -ArgumentList @("commit", "-m", "initial main")
        Invoke-TestGit -Repository $mainWork -ArgumentList @("remote", "add", "origin", $mainRemote)

        $modulesRoot = Join-Path $mainWork "modules"
        $gitModulesRoot = Join-Path $mainWork ".git\modules"
        New-Item -ItemType Directory -Path $modulesRoot, $gitModulesRoot -Force | Out-Null
        $gitmodulesLines = [System.Collections.Generic.List[string]]::new()

        for ($index = 1; $index -le $ChildCount; $index++) {
            $leafName = if ($index -eq 1) { "child" } else { "child$index" }
            $sectionName = if ($index -eq 1) { "render-engine" } else { "analytics-engine" }
            $childPath = Join-Path $modulesRoot $leafName
            $childGitDir = Join-Path $gitModulesRoot $sectionName
            Invoke-TestGitGlobal -ArgumentList @(
                "clone", "--separate-git-dir=$childGitDir", "-b", "release", $childRemote, $childPath
            )
            $remoteForConfig = $childRemote.Replace('\', '/')
            $gitmodulesLines.Add("[submodule `"$sectionName`"]")
            $gitmodulesLines.Add("`tpath = modules/$leafName")
            $gitmodulesLines.Add("`turl = $remoteForConfig")
            $gitmodulesLines.Add("`tbranch = $SubmoduleBranch")
        }

        Set-Content -LiteralPath (Join-Path $mainWork ".gitmodules") -Value $gitmodulesLines -Encoding utf8NoBOM
        Invoke-TestGit -Repository $mainWork -ArgumentList @("add", ".gitmodules", "modules")
        Invoke-TestGit -Repository $mainWork -ArgumentList @("commit", "-m", "add named submodules")
        Invoke-TestGit -Repository $mainWork -ArgumentList @("push", "-u", "origin", "developbim")

        return [PSCustomObject]@{
            Root = $Root
            Main = $mainWork
            MainRemote = $mainRemote
            ChildSource = $childWork
            ChildRemote = $childRemote
            FirstChild = Join-Path $modulesRoot "child"
            LogDirectory = Join-Path $Root "logs"
        }
    }

    function Invoke-ScriptUnderTest {
        param(
            [Parameter(Mandatory)][object]$Fixture,
            [string]$Branch = "developbim",
            [string]$Mode = "All",
            [switch]$DryRun,
            [switch]$Parallel,
            [switch]$SubmodulesOnly
        )

        $argumentList = @(
            "-NoProfile", "-File", $scriptUnderTest,
            "-MainDir", $Fixture.Main,
            "-Branch", $Branch,
            "-Mode", $Mode,
            "-RetryCount", "0",
            "-LogDir", $Fixture.LogDirectory,
            "-NoPause"
        )
        if ($DryRun) { $argumentList += "-DryRun" }
        if ($Parallel) { $argumentList += "-Parallel" }
        if ($SubmodulesOnly) { $argumentList += "-SubmodulesOnly" }

        $output = & pwsh @argumentList 2>&1 | Out-String
        return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

Describe "git_recursive_checkout_pull.ps1" {
    It "resolves a submodule whose section name differs from its path" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "named-path") -SubmoduleBranch "release"
        $result = Invoke-ScriptUnderTest -Fixture $fixture -DryRun -SubmodulesOnly

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'child\s+计划: git checkout release'
        $result.Output | Should -Match '\.gitmodules:\s+1'
    }

    It "implements branch dot by inheriting the parent target branch" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "inherited") -SubmoduleBranch "."
        $result = Invoke-ScriptUnderTest -Fixture $fixture -DryRun -SubmodulesOnly

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'child\s+计划: git checkout -b developbim'
        $result.Output | Should -Match 'branch = \.:\s+1'
    }

    It "rejects PullOnly when the current branch is not the target branch" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "pull-guard")
        $result = Invoke-ScriptUnderTest -Fixture $fixture -Branch "release" -Mode "PullOnly" -SubmodulesOnly

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '拒绝 pull：当前分支为 developbim，目标分支为 release'
    }

    It "blocks pull and descendants after a checkout failure" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "dependency-guard") -SubmoduleBranch "."
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("checkout", "-b", "conflict-target")
        Set-Content -LiteralPath (Join-Path $fixture.Main "README.md") -Value "target content" -Encoding utf8NoBOM
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("add", "README.md")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("commit", "-m", "target change")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("push", "-u", "origin", "conflict-target")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("checkout", "developbim")
        Set-Content -LiteralPath (Join-Path $fixture.Main "README.md") -Value "local uncommitted content" -Encoding utf8NoBOM

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Branch "conflict-target" -SubmodulesOnly
        $currentBranch = & git -C $fixture.Main branch --show-current

        $result.ExitCode | Should -Be 1
        $currentBranch | Should -Be "developbim"
        $result.Output | Should -Match 'checkout 未成功，禁止继续 pull'
        $result.Output | Should -Match '父仓库未成功完成，跳过此仓库及其后代'
    }

    It "checks out a local branch when the remote branch is absent" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "local-only") -SubmoduleBranch "local-only"
        Invoke-TestGit -Repository $fixture.FirstChild -ArgumentList @("branch", "local-only")

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Mode "CheckoutOnly" -SubmodulesOnly
        $childBranch = & git -C $fixture.FirstChild branch --show-current

        $result.ExitCode | Should -Be 0
        $childBranch | Should -Be "local-only"
        $result.Output | Should -Match 'checkout OK -> local-only'
    }

    It "uses the shared worker for parallel sibling submodules" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "parallel") -ChildCount 2
        $result = Invoke-ScriptUnderTest -Fixture $fixture -DryRun -Parallel -SubmodulesOnly

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'child\s+计划: git checkout release'
        $result.Output | Should -Match 'child2\s+计划: git checkout release'
        $result.Output | Should -Match '计划:\s+6'
    }

    It "returns exit code 2 for a missing main directory" {
        $missingDirectory = Join-Path $TestDrive "does-not-exist"
        $output = & pwsh -NoProfile -File $scriptUnderTest -MainDir $missingDirectory -NoPause 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 2
        $output | Should -Match '主目录不存在'
    }
}
