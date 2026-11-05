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
            [switch]$SubmodulesOnly,
            [switch]$KeepGoing,
            [string[]]$ExcludePatterns = @(),
            [hashtable]$Options = @{}
        )

        $parameters = @{
            MainDir = $Fixture.Main; Branch = $Branch; Mode = $Mode
            RetryCount = 0; RetryDelaySeconds = 0; LogDir = $Fixture.LogDirectory; NoPause = $true
        }
        if ($DryRun) { $parameters.DryRun = $true }
        if ($Parallel) { $parameters.Parallel = $true }
        if ($SubmodulesOnly) { $parameters.SubmodulesOnly = $true }
        if ($KeepGoing) { $parameters.KeepGoing = $true }
        if ($ExcludePatterns.Count -gt 0) { $parameters.ExcludePatterns = $ExcludePatterns }
        foreach ($key in $Options.Keys) { $parameters[$key] = $Options[$key] }

        # -File 不能完整传递数组参数；在独立进程中反序列化后 splat，保留真实参数类型。
        $serialized = [System.Management.Automation.PSSerializer]::Serialize(@{ Path = $scriptUnderTest; Parameters = $parameters })
        $payload = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($serialized))
        $commandText = '$ErrorActionPreference = "Stop"; try { $call = [System.Management.Automation.PSSerializer]::Deserialize([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String("' + $payload + '"))); $parameters = $call.Parameters; & $call.Path @parameters; exit $LASTEXITCODE } catch { Write-Error $_ -ErrorAction Continue; exit 1 }'
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($commandText))
        $output = & pwsh -NoProfile -OutputFormat Text -EncodedCommand $encodedCommand 2>&1 | Out-String
        return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }

    function Invoke-TestMainSourceSetup {
        param([object]$Fixture)
        $source = Join-Path $Fixture.Root "main-source"
        Invoke-TestGitGlobal -ArgumentList @("clone", "-b", "developbim", $Fixture.MainRemote, $source)
        Invoke-TestGit -Repository $source -ArgumentList @("config", "user.name", "Codex Test")
        Invoke-TestGit -Repository $source -ArgumentList @("config", "user.email", "codex@example.invalid")
        return $source
    }

    function Add-TestNestedSubmodule {
        param([object]$Fixture)
        $parentGitDir = & git -C $Fixture.FirstChild rev-parse --absolute-git-dir
        $nestedGitDir = Join-Path $parentGitDir "modules/nested"
        New-Item -ItemType Directory -Path (Split-Path $nestedGitDir -Parent) -Force | Out-Null
        $nested = Join-Path $Fixture.FirstChild "nested"
        Invoke-TestGitGlobal -ArgumentList @("clone", "--separate-git-dir=$nestedGitDir", "-b", "release", $Fixture.ChildRemote, $nested)
        Set-Content -LiteralPath (Join-Path $Fixture.FirstChild ".gitmodules") -Value @(
            '[submodule "nested"]', 'path = nested', "url = $($Fixture.ChildRemote.Replace('\', '/'))", 'branch = release'
        ) -Encoding utf8NoBOM
        Invoke-TestGit -Repository $Fixture.FirstChild -ArgumentList @("config", "user.name", "Codex Test")
        Invoke-TestGit -Repository $Fixture.FirstChild -ArgumentList @("config", "user.email", "codex@example.invalid")
        Invoke-TestGit -Repository $Fixture.FirstChild -ArgumentList @("add", ".gitmodules", "nested")
        Invoke-TestGit -Repository $Fixture.FirstChild -ArgumentList @("commit", "-m", "add nested submodule")
        Invoke-TestGit -Repository $Fixture.FirstChild -ArgumentList @("push", "origin", "release")
        return $nested
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

    It "handles parent pull failure in <Mode> with KeepGoing=<Continue>" -ForEach @(
        @{ Mode = "All"; Continue = $false }
        @{ Mode = "All"; Continue = $true }
        @{ Mode = "PullOnly"; Continue = $false }
        @{ Mode = "PullOnly"; Continue = $true }
    ) {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "pull-failure-$Mode-$Continue")
        $mainSource = Invoke-TestMainSourceSetup -Fixture $fixture
        Set-Content -LiteralPath (Join-Path $mainSource "README.md") -Value "remote update" -Encoding utf8NoBOM
        Invoke-TestGit -Repository $mainSource -ArgumentList @("commit", "-am", "remote main update")
        Invoke-TestGit -Repository $mainSource -ArgumentList @("push", "origin", "developbim")
        Set-Content -LiteralPath (Join-Path $fixture.Main "README.md") -Value "uncommitted local update" -Encoding utf8NoBOM
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("config", "merge.autoStash", "true")

        Invoke-TestGit -Repository $fixture.ChildSource -ArgumentList @("checkout", "release")
        Set-Content -LiteralPath (Join-Path $fixture.ChildSource "README.md") -Value "child remote update" -Encoding utf8NoBOM
        Invoke-TestGit -Repository $fixture.ChildSource -ArgumentList @("commit", "-am", "remote child update")
        Invoke-TestGit -Repository $fixture.ChildSource -ArgumentList @("push", "origin", "release")
        $expectedChildHead = & git -C $fixture.ChildSource rev-parse HEAD
        $originalChildHead = & git -C $fixture.FirstChild rev-parse HEAD

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Mode $Mode -KeepGoing:$Continue
        $childHead = & git -C $fixture.FirstChild rev-parse HEAD

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'main\s+pull 失败:'
        if ($Continue) {
            $childHead | Should -Be $expectedChildHead
            $result.Output | Should -Match 'child\s+pull OK'
            $result.Output | Should -Not -Match '父仓库未成功完成'
        } else {
            $childHead | Should -Be $originalChildHead
            $result.Output | Should -Match '父仓库未成功完成，跳过此仓库及其后代'
        }
        Get-Content -LiteralPath (Join-Path $fixture.Main "README.md") | Should -Be "uncommitted local update"
    }

    It "continues child operations after a parent checkout failure but still blocks the parent pull" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "continue-checkout-failure")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("checkout", "-b", "conflict-target")
        Set-Content -LiteralPath (Join-Path $fixture.Main "README.md") -Value "target content" -Encoding utf8NoBOM
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("commit", "-am", "target change")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("push", "-u", "origin", "conflict-target")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("checkout", "developbim")
        Set-Content -LiteralPath (Join-Path $fixture.Main "README.md") -Value "local uncommitted content" -Encoding utf8NoBOM

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Branch "conflict-target" -KeepGoing

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'checkout 未成功，禁止继续 pull'
        $result.Output | Should -Match 'child\s+checkout OK -> release'
        $result.Output | Should -Match 'child\s+pull OK'
        (& git -C $fixture.Main branch --show-current) | Should -Be "developbim"
    }

    It "uses the parent working tree in DryRun when parent fetch fails and continuation is enabled" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "continue-dryrun") -SubmoduleBranch "."
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("remote", "set-url", "origin", (Join-Path $fixture.Root "missing.git"))
        $originalChildHead = & git -C $fixture.FirstChild rev-parse HEAD

        $result = Invoke-ScriptUnderTest -Fixture $fixture -DryRun -KeepGoing

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'child\s+计划: git checkout -b developbim'
        $result.Output | Should -Match 'child\s+计划: git pull --no-rebase --no-autostash --no-edit --no-recurse-submodules origin developbim'
        (& git -C $fixture.FirstChild branch --show-current) | Should -Be "release"
        (& git -C $fixture.FirstChild rev-parse HEAD) | Should -Be $originalChildHead
    }

    It "uses the shared worker for parallel sibling submodules" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "parallel") -ChildCount 2
        $result = Invoke-ScriptUnderTest -Fixture $fixture -DryRun -Parallel -SubmodulesOnly

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'child\s+计划: git checkout release'
        $result.Output | Should -Match 'child2\s+计划: git checkout release'
        $result.Output | Should -Match '计划:\s+6'
    }

    It "treats a missing target branch as skip instead of dependency failure" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "missing-branch") -SubmoduleBranch "ghost"
        $result = Invoke-ScriptUnderTest -Fixture $fixture

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match '无目标分支，跳过 pull'
        $result.Output | Should -Not -Match '父仓库未成功完成'
    }

    It "skips submodules of a SubmodulesOnly-skipped standalone with KeepGoing=<Continue>" -ForEach @(
        @{ Continue = $false }
        @{ Continue = $true }
    ) {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "standalone-skip-$Continue") -SubmoduleBranch "release"
        $standalone = Join-Path $fixture.Main "extra"
        Invoke-TestGitGlobal -ArgumentList @("init", "--initial-branch=developbim", $standalone)
        Invoke-TestGit -Repository $standalone -ArgumentList @("config", "user.name", "Codex Test")
        Invoke-TestGit -Repository $standalone -ArgumentList @("config", "user.email", "codex@example.invalid")
        $helperModulesRoot = Join-Path $standalone ".git\modules"
        New-Item -ItemType Directory -Path $helperModulesRoot -Force | Out-Null
        Invoke-TestGitGlobal -ArgumentList @(
            "clone", "--separate-git-dir=$(Join-Path $helperModulesRoot "helper")", "-b", "release", $fixture.ChildRemote, (Join-Path $standalone "helper")
        )
        # 在父仓库 index 中登记 gitlink，git 才会报告 superproject 关系
        Invoke-TestGit -Repository $standalone -ArgumentList @("add", "helper")
        $result = Invoke-ScriptUnderTest -Fixture $fixture -SubmodulesOnly -KeepGoing:$Continue

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'extra\s+非主仓库且非子模块'
        $result.Output | Should -Match 'helper\s+父仓库已被排除或跳过，跳过此仓库及其后代'
        $result.Output | Should -Not -Match '父仓库未成功完成'
    }

    It "returns exit code 2 for a missing main directory" {
        $missingDirectory = Join-Path $TestDrive "does-not-exist"
        $output = & pwsh -NoProfile -File $scriptUnderTest -MainDir $missingDirectory -NoPause 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 2
        $output | Should -Match '主目录不存在'
    }

    It "uses local metadata for CheckoutOnly DryRun and remote metadata after a planned pull" -ForEach @(
        @{ Mode = "CheckoutOnly"; ExpectedBranch = "release" }
        @{ Mode = "All"; ExpectedBranch = "developbim" }
    ) {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "metadata-$Mode")
        $source = Invoke-TestMainSourceSetup -Fixture $fixture
        Invoke-TestGit -Repository $source -ArgumentList @("config", "--file", ".gitmodules", "submodule.render-engine.branch", "developbim")
        Invoke-TestGit -Repository $source -ArgumentList @("commit", "-am", "change child branch remotely")
        Invoke-TestGit -Repository $source -ArgumentList @("push", "origin", "developbim")

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Mode $Mode -DryRun

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match "child\s+计划: git checkout (?:-b )?$ExpectedBranch"
        (& git -C $fixture.Main config --file .gitmodules submodule.render-engine.branch) | Should -Be "release"
    }

    It "rejects case differences in PullOnly branch names" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "branch-case")
        $result = Invoke-ScriptUnderTest -Fixture $fixture -Mode PullOnly -Branch DEVELOPBIM

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '拒绝 pull：当前分支为 developbim，目标分支为 DEVELOPBIM'
    }

    It "continues parallel siblings after parent failure with literal bracket paths" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "parallel [literal]") -ChildCount 2
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("remote", "set-url", "origin", (Join-Path $fixture.Root "missing.git"))

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Parallel -KeepGoing

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'child\s+pull OK'
        $result.Output | Should -Match 'child2\s+pull OK'
    }

    It "does not let recursive Git configuration change an excluded submodule" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "no-recursion")
        Invoke-TestGit -Repository $fixture.FirstChild -ArgumentList @("checkout", "developbim")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("config", "submodule.recurse", "true")

        $result = Invoke-ScriptUnderTest -Fixture $fixture -ExcludePatterns "modules/child"

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'child\s+排除:'
        (& git -C $fixture.FirstChild branch --show-current) | Should -Be "developbim"
    }

    It "reports malformed gitmodules as failure rather than a removed submodule" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "malformed-config")
        Set-Content -LiteralPath (Join-Path $fixture.Main ".gitmodules") -Value '[submodule "broken"' -Encoding utf8NoBOM

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Mode CheckoutOnly -KeepGoing

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '读取父仓库 \.gitmodules 失败'
        $result.Output | Should -Not -Match '跳过已从目标版本移除的子模块'
    }

    It "normalizes dot-prefixed submodule paths" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "dot-path")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("config", "--file", ".gitmodules", "submodule.render-engine.path", "./modules/child")

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Mode CheckoutOnly

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'child\s+checkout OK -> release'
    }

    It "keeps exclusion status through nested submodules" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "nested-excluded")
        $nested = Add-TestNestedSubmodule -Fixture $fixture

        $result = Invoke-ScriptUnderTest -Fixture $fixture -ExcludePatterns "main" -KeepGoing

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Not -Match '父仓库未成功完成'
        $result.Output | Should -Match 'nested\s+父仓库已被排除或跳过'
        (& git -C $nested branch --show-current) | Should -Be "release"
    }

    It "continues nested submodules when their direct parent fails" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "nested-continue")
        $nested = Add-TestNestedSubmodule -Fixture $fixture
        Invoke-TestGit -Repository $fixture.FirstChild -ArgumentList @("remote", "set-url", "origin", (Join-Path $fixture.Root "missing.git"))

        $result = Invoke-ScriptUnderTest -Fixture $fixture -KeepGoing

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'nested\s+pull OK'
        (& git -C $nested branch --show-current) | Should -Be "release"
    }

    It "allows children when PullOnly skips a parent whose remote branch is absent" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "pull-skip-parent")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("checkout", "-b", "local-only")

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Mode PullOnly -Branch local-only

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'main\s+远端 origin 无分支 local-only，跳过 pull'
        $result.Output | Should -Match 'child\s+pull OK'
    }

    It "returns failure when all discovered repositories are excluded" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "all-excluded")
        $result = Invoke-ScriptUnderTest -Fixture $fixture -ExcludePatterns '*'

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '所有仓库均被跳过，未执行任何操作'
    }

    It "does not traverse junctions to repositories outside MainDir" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "junction")
        $outside = Join-Path $fixture.Root "outside"
        Invoke-TestGitGlobal -ArgumentList @("clone", "-b", "release", $fixture.ChildRemote, $outside)
        New-Item -ItemType Junction -Path (Join-Path $fixture.Main "linked-repo") -Target $outside | Out-Null

        $result = Invoke-ScriptUnderTest -Fixture $fixture

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Not -Match 'linked-repo'
        (& git -C $outside branch --show-current) | Should -Be "release"
    }

    It "uses the parameter branch when a registered submodule has no branch setting" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "branch-fallback")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("config", "--file", ".gitmodules", "--unset", "submodule.render-engine.branch")

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Mode CheckoutOnly

        $result.ExitCode | Should -Be 0
        (& git -C $fixture.FirstChild branch --show-current) | Should -Be "developbim"
        $result.Output | Should -Match '回退参数:\s+1'
    }

    It "skips a submodule removed by a remote update" -ForEach @(
        @{ DryRun = $false }
        @{ DryRun = $true }
    ) {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "removed-$DryRun")
        $source = Invoke-TestMainSourceSetup -Fixture $fixture
        Invoke-TestGit -Repository $source -ArgumentList @("rm", "--cached", "modules/child")
        Invoke-TestGit -Repository $source -ArgumentList @("rm", ".gitmodules")
        Invoke-TestGit -Repository $source -ArgumentList @("commit", "-m", "remove submodule")
        Invoke-TestGit -Repository $source -ArgumentList @("push", "origin", "developbim")
        $originalChildHead = & git -C $fixture.FirstChild rev-parse HEAD

        $result = Invoke-ScriptUnderTest -Fixture $fixture -DryRun:$DryRun -KeepGoing

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'child\s+.*跳过已从目标版本移除的子模块'
        (& git -C $fixture.FirstChild rev-parse HEAD) | Should -Be $originalChildHead
        (& git -C $fixture.FirstChild branch --show-current) | Should -Be "release"
    }

    It "processes independent repositories in container mode" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "container")
        $container = Join-Path $fixture.Root "container"
        New-Item -ItemType Directory -Path $container -Force | Out-Null
        $standalone = Join-Path $container "standalone"
        Invoke-TestGitGlobal -ArgumentList @("clone", "-b", "release", $fixture.ChildRemote, $standalone)

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Options @{ MainDir = $container }

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match '扫描容器模式'
        $result.Output | Should -Match 'standalone\s+pull OK'
        (& git -C $standalone branch --show-current) | Should -Be "developbim"
    }

    It "continues standalone repositories after a main repository failure without KeepGoing" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "standalone-independent")
        $standalone = Join-Path $fixture.Main "extra"
        Invoke-TestGitGlobal -ArgumentList @("clone", "-b", "release", $fixture.ChildRemote, $standalone)
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("remote", "set-url", "origin", (Join-Path $fixture.Root "missing.git"))

        $result = Invoke-ScriptUnderTest -Fixture $fixture

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'extra\s+pull OK'
        $result.Output | Should -Match 'child\s+父仓库未成功完成'
        (& git -C $standalone branch --show-current) | Should -Be "developbim"
    }

    It "rejects PullOnly in detached HEAD" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "detached")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("checkout", "--detach", "HEAD")
        $originalHead = & git -C $fixture.Main rev-parse HEAD

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Mode PullOnly

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '拒绝 pull：当前分支为 DETACHED HEAD'
        (& git -C $fixture.Main rev-parse HEAD) | Should -Be $originalHead
    }

    It "honors scan depth and writes a completed log" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "max-depth") -SubmoduleBranch "."

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Options @{ MaxDepth = 0 }

        $result.ExitCode | Should -Be 0
        (& git -C $fixture.FirstChild branch --show-current) | Should -Be "release"
        $result.Output | Should -Match '子模块 0'
        $logs = @(Get-ChildItem -LiteralPath $fixture.LogDirectory -Filter '*.log')
        $logs.Count | Should -Be 1
        Get-Content -LiteralPath $logs[0].FullName -Raw | Should -Match '执行完毕.*失败=0'
    }

    It "honors custom remote names" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "custom-remote")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("remote", "rename", "origin", "upstream")
        Invoke-TestGit -Repository $fixture.FirstChild -ArgumentList @("remote", "rename", "origin", "upstream")

        $result = Invoke-ScriptUnderTest -Fixture $fixture -Options @{ Remote = "upstream" }

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'child\s+pull OK'
    }

    It "honors multiple exclusion patterns" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "multiple-exclusions") -ChildCount 2

        $result = Invoke-ScriptUnderTest -Fixture $fixture -ExcludePatterns @('not-present', 'modules/child')

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'child\s+排除:'
        $result.Output | Should -Match 'child2\s+排除:'
    }

    It "limits retry attempts on remote failure" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "retry-limit")
        Invoke-TestGit -Repository $fixture.Main -ArgumentList @("remote", "set-url", "origin", (Join-Path $fixture.Root "missing.git"))

        $tracePath = Join-Path $fixture.Root "git-trace.log"
        $previousTrace = $env:GIT_TRACE
        try {
            $env:GIT_TRACE = $tracePath.Replace('\', '/')
            $result = Invoke-ScriptUnderTest -Fixture $fixture -Options @{ RetryCount = 1; RetryDelaySeconds = 0 }
        } finally {
            $env:GIT_TRACE = $previousTrace
        }

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '远端检查或 fetch 失败（共尝试 2 次）'
        $result.Output | Should -Match 'checkout 未成功，禁止继续 pull'
        @(Select-String -LiteralPath $tracePath -Pattern 'built-in: git ls-remote').Count | Should -Be 2
    }

    It "fails when the main target branch is absent everywhere" {
        $fixture = Invoke-TestFixtureSetup -Root (Join-Path $TestDrive "main-missing-branch")
        $result = Invoke-ScriptUnderTest -Fixture $fixture -Branch ghost -KeepGoing

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '远端和本地均无分支 ghost，跳过 checkout'
        $result.Output | Should -Match '所有仓库均被跳过，未执行任何操作'
        (& git -C $fixture.FirstChild branch --show-current) | Should -Be "release"
    }

    It "returns exit code 2 for an empty scan directory" {
        $empty = Join-Path $TestDrive "empty"
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        $fixture = [PSCustomObject]@{ Main = $empty; LogDirectory = Join-Path $TestDrive "empty-logs" }
        $result = Invoke-ScriptUnderTest -Fixture $fixture

        $result.ExitCode | Should -Be 2
        $result.Output | Should -Match '未找到任何 Git 仓库'
    }

    It "rejects invalid numeric parameters and unknown switches" -ForEach @(
        @{ Option = 'RetryCount'; Value = -1 }
        @{ Option = 'ThrottleLimit'; Value = 0 }
        @{ Option = 'MaxDepth'; Value = -1 }
        @{ Option = 'NoSuchOption'; Value = $true }
    ) {
        $fixture = [PSCustomObject]@{ Main = $TestDrive; LogDirectory = Join-Path $TestDrive "unused-logs" }
        $result = Invoke-ScriptUnderTest -Fixture $fixture -Options @{ $Option = $Value }

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match $Option
        Test-Path -LiteralPath $fixture.LogDirectory | Should -BeFalse
    }
}
