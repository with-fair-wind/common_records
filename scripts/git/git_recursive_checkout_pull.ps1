<#
.SYNOPSIS
安全地批量切换并拉取主仓库、已初始化子模块和可选的独立嵌套仓库。

.DESCRIPTION
主仓库和独立仓库使用 Branch 参数；子模块根据直接父仓库目标版本中的
.gitmodules branch 配置选择分支，branch = . 时继承父仓库目标分支。
脚本按父仓库到子模块的顺序执行，checkout 未成功时禁止继续 pull。

脚本不会克隆仓库、初始化子模块、按 gitlink commit 检出、自动 stash/reset，
也不会自动解决冲突。DryRun 会 fetch 远端引用以准确解析目标 .gitmodules，
但不会 checkout、pull 或修改工作树。
#>
#Requires -Version 7.0

param(
    [string]$MainDir = (Join-Path (Get-Location) "main"),
    [string]$Branch = "developbim",
    [string]$Remote = "origin",
    [ValidateSet("All", "CheckoutOnly", "PullOnly")]
    [string]$Mode = "All",
    [ValidateRange(0, 2147483647)][int]$RetryCount = 2,
    [ValidateRange(0, 2147483647)][int]$RetryDelaySeconds = 2,
    [switch]$Parallel,
    [ValidateRange(1, 2147483647)][int]$ThrottleLimit = 6,
    [switch]$DryRun,
    [string]$LogDir = (Join-Path $PSScriptRoot "logs"),
    [string[]]$ExcludePatterns = @(),
    [ValidateRange(0, 2147483647)][int]$MaxDepth = 5,
    [switch]$SubmodulesOnly,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
$defaultExcludePatterns = @("BIM\ZwBm", "BIM\BmDb")
$script:AdditionalExcludePatterns = $ExcludePatterns

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "未找到 git 命令，请先安装 Git 并加入 PATH。" -ErrorAction Continue
    exit 2
}
if (-not (Test-Path -LiteralPath $MainDir -PathType Container)) {
    Write-Error "主目录不存在: $MainDir" -ErrorAction Continue
    exit 2
}

$MainDir = [System.IO.Path]::GetFullPath($MainDir).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $LogDir -PathType Container)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}
$timeTag = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $LogDir "git_checkout_pull_$timeTag.log"

$script:TotalWidth = 72
$script:Stats = @{ Success = 0; Failed = 0; Skipped = 0; DependencyFailed = 0; Planned = 0 }
$script:FailedRepos = [System.Collections.Generic.List[object]]::new()
$script:RepoIndex = @{}
$script:BranchStats = @{ Gitmodules = 0; Inherited = 0; Fallback = 0; Parameter = 0 }

function Write-GitBatchLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "OK")][string]$Level = "INFO"
    )
    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Message
    Add-Content -LiteralPath $script:logFile -Value $line -ErrorAction SilentlyContinue
}

function Write-Banner {
    param([string]$Text)
    $innerWidth = $script:TotalWidth - 2
    $pad = [Math]::Max(0, $innerWidth - $Text.Length - 2)
    $left = [Math]::Floor($pad / 2)
    $right = $pad - $left
    Write-Host ""
    Write-Host "╔$('═' * $innerWidth)╗" -ForegroundColor Cyan
    Write-Host "║$(' ' * $left) $Text $(' ' * $right)║" -ForegroundColor Cyan
    Write-Host "╚$('═' * $innerWidth)╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Text)
    $line = "── $Text $('─' * [Math]::Max(0, $script:TotalWidth - $Text.Length - 5))"
    Write-Host ""
    Write-Host $line -ForegroundColor DarkCyan
}

function Write-Status {
    param(
        [string]$RepoName,
        [string]$Message,
        [ValidateSet("OK", "FAIL", "SKIP", "DEPENDENCY", "PLAN", "INFO", "WARN")][string]$Level = "INFO"
    )
    $icon = switch ($Level) {
        "OK" { "[+]" }; "FAIL" { "[X]" }; "SKIP" { "[-]" }; "DEPENDENCY" { "[D]" }
        "PLAN" { "[~]" }; "WARN" { "[!]" }; default { "[*]" }
    }
    $color = switch ($Level) {
        "OK" { "Green" }; "FAIL" { "Red" }; "SKIP" { "DarkYellow" }; "DEPENDENCY" { "DarkYellow" }
        "PLAN" { "Magenta" }; "WARN" { "Yellow" }; default { "White" }
    }
    $nameDisplay = if ($RepoName.Length -gt 28) { $RepoName.Substring(0, 25) + "..." } else { $RepoName }
    Write-Host "$icon $($nameDisplay.PadRight(28))" -ForegroundColor $color -NoNewline
    Write-Host " $Message" -ForegroundColor Gray
    $logLevel = switch ($Level) {
        "OK" { "OK" }; "FAIL" { "ERROR" }; "SKIP" { "WARN" }; "DEPENDENCY" { "WARN" }
        "WARN" { "WARN" }; default { "INFO" }
    }
    Write-GitBatchLog -Message "$RepoName | $Message" -Level $logLevel
}

function Write-Detail {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

function Get-NormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Get-PathKey {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-NormalizedPath -Path $Path).ToLowerInvariant()
}

function Get-RelativePath {
    param([string]$BasePath, [string]$TargetPath)
    $base = Get-NormalizedPath -Path $BasePath
    $target = Get-NormalizedPath -Path $TargetPath
    if ($target -ieq $base) { return "." }
    $prefix = $base + [System.IO.Path]::DirectorySeparatorChar
    if ($target.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $target.Substring($prefix.Length)
    }
    return $target
}

function Find-GitRepo {
    param([string]$Path, [int]$CurrentDepth = 0)
    if ($CurrentDepth -gt $MaxDepth) { return }

    if (Test-Path -LiteralPath (Join-Path $Path ".git")) {
        $relativePath = Get-RelativePath -BasePath $MainDir -TargetPath $Path
        [PSCustomObject]@{
            Path = Get-NormalizedPath -Path $Path
            Name = Split-Path $Path -Leaf
            RelativePath = $relativePath
            Type = "Standalone"
            ParentPath = $null
            SubmoduleName = $null
            Depth = if ($relativePath -eq ".") { 0 } else { ($relativePath -split '[\\/]').Count }
            TargetBranch = $null
            BranchSource = $null
            MetadataRef = $null
            CheckoutStatus = $null
            PullStatus = $null
            ReadyForChildren = $false
            Excluded = $false
        }
    }

    foreach ($child in @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)) {
        if ($child.Name -in @("node_modules", ".git", "__pycache__", ".vs", ".idea")) { continue }
        Find-GitRepo -Path $child.FullName -CurrentDepth ($CurrentDepth + 1)
    }
}

function Test-ShouldExclude {
    param([string]$RelativePath)
    $matchTargets = @($RelativePath)
    if ($RelativePath -eq ".") {
        $topLeaf = Split-Path $MainDir -Leaf
        if ($topLeaf -and $matchTargets -notcontains $topLeaf) { $matchTargets += $topLeaf }
    }
    foreach ($pattern in @($defaultExcludePatterns + $script:AdditionalExcludePatterns)) {
        if (-not $pattern) { continue }
        $normalized = $pattern.Trim().Replace('/', '\')
        foreach ($target in $matchTargets) {
            if ($target -like "*$normalized*") { return $true }
        }
    }
    return $false
}

function Get-RepoPlan {
    param([string]$Path)
    $key = Get-PathKey -Path $Path
    if ($script:RepoIndex.ContainsKey($key)) { return $script:RepoIndex[$key] }
    return $null
}

function Initialize-RepoPlan {
    param([object[]]$Repos)
    foreach ($repo in $Repos) {
        $script:RepoIndex[(Get-PathKey -Path $repo.Path)] = $repo
    }
    foreach ($repo in $Repos) {
        if ($repo.Path -ieq $MainDir) {
            $repo.Type = "Main"
            $repo.Depth = 0
            continue
        }
        $superOutput = & git -C $repo.Path rev-parse --show-superproject-working-tree 2>$null
        $superCode = $LASTEXITCODE
        $super = $superOutput | Select-Object -First 1
        if ($superCode -eq 0 -and $super) {
            $superPath = Get-NormalizedPath -Path "$($super.Trim())"
            $rootPrefix = $MainDir + [System.IO.Path]::DirectorySeparatorChar
            if ($superPath -ieq $MainDir -or $superPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $repo.Type = "Submodule"
                $repo.ParentPath = $superPath
            }
        }
    }
}

function Get-GitmodulesConfigArgument {
    param([object]$ParentRepo)
    $gitConfigArguments = @("-C", $ParentRepo.Path, "config")
    if ($DryRun) {
        if (-not $ParentRepo.MetadataRef) { return $null }
        return @($gitConfigArguments + @("--blob", "$($ParentRepo.MetadataRef):.gitmodules"))
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ParentRepo.Path ".gitmodules") -PathType Leaf)) {
        return $null
    }
    return @($gitConfigArguments + @("--file", ".gitmodules"))
}

function Get-TargetBranch {
    param([object]$Repo)
    if ($Repo.Type -ne "Submodule") {
        return [PSCustomObject]@{ Valid = $true; Registered = $false; Branch = $Branch; Source = "Parameter"; SubmoduleName = $null; Message = $null }
    }

    $parent = Get-RepoPlan -Path $Repo.ParentPath
    if ($null -eq $parent) {
        return [PSCustomObject]@{ Valid = $false; Registered = $false; Branch = $null; Source = $null; SubmoduleName = $null; Message = "未发现直接父仓库: $($Repo.ParentPath)" }
    }
    $baseArgs = Get-GitmodulesConfigArgument -ParentRepo $parent
    if ($null -eq $baseArgs) {
        return [PSCustomObject]@{ Valid = $true; Registered = $false; Branch = $Branch; Source = "Fallback"; SubmoduleName = $null; Message = "父仓库目标版本不存在 .gitmodules" }
    }

    $keys = & git @baseArgs --name-only --get-regexp '^submodule\..*\.path$' 2>$null
    if ($LASTEXITCODE -ne 0) {
        return [PSCustomObject]@{ Valid = $true; Registered = $false; Branch = $Branch; Source = "Fallback"; SubmoduleName = $null; Message = "未找到子模块路径配置" }
    }

    $childRelative = (Get-RelativePath -BasePath $parent.Path -TargetPath $Repo.Path).Replace('\', '/').TrimEnd('/')
    foreach ($pathKeyValue in @($keys)) {
        $pathKey = "$pathKeyValue".Trim()
        if (-not $pathKey.StartsWith("submodule.", [System.StringComparison]::OrdinalIgnoreCase) -or
            -not $pathKey.EndsWith(".path", [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $declaredPathOutput = & git @baseArgs --get $pathKey 2>$null
        if ($LASTEXITCODE -ne 0) { continue }
        $declaredPath = "$($declaredPathOutput | Select-Object -First 1)".Trim().Replace('\', '/').TrimEnd('/')
        if ($declaredPath -ine $childRelative) { continue }

        $submoduleName = $pathKey.Substring(10, $pathKey.Length - 15)
        $declaredBranchOutput = & git @baseArgs --get "submodule.$submoduleName.branch" 2>$null
        $branchCode = $LASTEXITCODE
        $declaredBranch = "$($declaredBranchOutput | Select-Object -First 1)".Trim()
        if ($branchCode -eq 0 -and $declaredBranch) {
            if ($declaredBranch -eq ".") {
                return [PSCustomObject]@{ Valid = $true; Registered = $true; Branch = $parent.TargetBranch; Source = "Inherited"; SubmoduleName = $submoduleName; Message = $null }
            }
            return [PSCustomObject]@{ Valid = $true; Registered = $true; Branch = $declaredBranch; Source = "Gitmodules"; SubmoduleName = $submoduleName; Message = $null }
        }
        return [PSCustomObject]@{ Valid = $true; Registered = $true; Branch = $Branch; Source = "Fallback"; SubmoduleName = $submoduleName; Message = $null }
    }

    return [PSCustomObject]@{ Valid = $true; Registered = $false; Branch = $Branch; Source = "Fallback"; SubmoduleName = $null; Message = "父仓库目标版本未登记此子模块" }
}

# 顺序和并行模式共用同一工作单元。
$script:OperationWorker = {
    param($RepoPath, $RepoName, $Operation, $TargetBranch, $RemoteName, $MaxRetry, $RetryDelay, $UseDryRun, $AssumeTargetCheckedOut)
    $ErrorActionPreference = "Continue"
    $workerRepoName = $RepoName
    $workerMaxRetry = $MaxRetry
    $workerRetryDelay = $RetryDelay

    function ConvertTo-WorkerResult {
        param($Status, $Message, $ExitCode = 0, $RemoteExists = $null, $LocalExists = $null, $MetadataRef = $null)
        [PSCustomObject]@{
            RepoPath = $RepoPath; RepoName = $workerRepoName; Operation = $Operation; TargetBranch = $TargetBranch
            Status = $Status; ExitCode = $ExitCode; Message = $Message
            RemoteExists = $RemoteExists; LocalExists = $LocalExists; MetadataRef = $MetadataRef
        }
    }

    function Sync-RemoteBranch {
        $remoteUrl = & git remote get-url $RemoteName 2>&1
        $remoteCode = $LASTEXITCODE
        if ($remoteCode -ne 0) {
            return [PSCustomObject]@{ Status = "FAIL"; ExitCode = $remoteCode; Message = "远程 $RemoteName 不存在: $(($remoteUrl | Out-String).Trim())" }
        }

        $maxAttempts = $workerMaxRetry + 1
        $lastCode = 1
        $errorText = ""
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            $remoteOutput = & git ls-remote --exit-code --heads $RemoteName "refs/heads/$TargetBranch" 2>&1
            $lastCode = $LASTEXITCODE
            if ($lastCode -eq 2) {
                return [PSCustomObject]@{ Status = "MISSING"; ExitCode = 0; Message = "远端 $RemoteName 无分支 $TargetBranch" }
            }
            if ($lastCode -eq 0) {
                $refspec = "+refs/heads/$TargetBranch`:refs/remotes/$RemoteName/$TargetBranch"
                $fetchOutput = & git fetch --quiet $RemoteName $refspec 2>&1
                $lastCode = $LASTEXITCODE
                if ($lastCode -eq 0) {
                    return [PSCustomObject]@{ Status = "OK"; ExitCode = 0; Message = ""; MetadataRef = "refs/remotes/$RemoteName/$TargetBranch" }
                }
                $errorText = ($fetchOutput | Out-String).Trim()
            } else {
                $errorText = ($remoteOutput | Out-String).Trim()
            }
            if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds $workerRetryDelay }
        }
        return [PSCustomObject]@{ Status = "FAIL"; ExitCode = $lastCode; Message = "远端检查或 fetch 失败（共尝试 $maxAttempts 次）: $errorText" }
    }

    Push-Location $RepoPath
    try {
        $branchCheck = & git check-ref-format --branch $TargetBranch 2>&1
        $branchCode = $LASTEXITCODE
        if ($branchCode -ne 0) {
            return ConvertTo-WorkerResult -Status "FAIL" -ExitCode $branchCode -Message "非法目标分支名 $TargetBranch：$(($branchCheck | Out-String).Trim())"
        }

        & git show-ref --verify --quiet "refs/heads/$TargetBranch" 2>$null
        $localExists = ($LASTEXITCODE -eq 0)

        if ($Operation -eq "pull" -and -not ($UseDryRun -and $AssumeTargetCheckedOut)) {
            $currentOutput = & git symbolic-ref --quiet --short HEAD 2>&1
            $currentCode = $LASTEXITCODE
            $currentBranch = "$($currentOutput | Select-Object -First 1)".Trim()
            if ($currentCode -ne 0 -or $currentBranch -ine $TargetBranch) {
                $displayCurrent = if ($currentBranch) { $currentBranch } else { "DETACHED HEAD" }
                return ConvertTo-WorkerResult -Status "FAIL" -ExitCode 1 -LocalExists $localExists -Message "拒绝 pull：当前分支为 $displayCurrent，目标分支为 $TargetBranch"
            }
        }

        $sync = Sync-RemoteBranch
        if ($sync.Status -eq "FAIL") {
            return ConvertTo-WorkerResult -Status "FAIL" -ExitCode $sync.ExitCode -LocalExists $localExists -Message $sync.Message
        }

        $remoteExists = ($sync.Status -eq "OK")
        $metadataRef = if ($remoteExists) { $sync.MetadataRef } elseif ($localExists) { "refs/heads/$TargetBranch" } else { $null }

        if ($Operation -eq "checkout") {
            if (-not $remoteExists -and -not $localExists) {
                return ConvertTo-WorkerResult -Status "SKIP" -RemoteExists $false -LocalExists $false -Message "远端和本地均无分支 $TargetBranch，跳过 checkout"
            }
            $description = if ($localExists) { "git checkout $TargetBranch" } else { "git checkout -b $TargetBranch --track $RemoteName/$TargetBranch" }
            if ($UseDryRun) {
                $suffix = if ($remoteExists) { "" } else { "；远端分支不存在，仅切换本地分支" }
                return ConvertTo-WorkerResult -Status "DRYRUN" -RemoteExists $remoteExists -LocalExists $localExists -MetadataRef $metadataRef -Message "计划: $description$suffix"
            }

            $checkoutArgs = if ($localExists) { @("checkout", $TargetBranch) } else { @("checkout", "-b", $TargetBranch, "--track", "$RemoteName/$TargetBranch") }
            $checkoutOutput = & git @checkoutArgs 2>&1
            $checkoutCode = $LASTEXITCODE
            if ($checkoutCode -ne 0) {
                return ConvertTo-WorkerResult -Status "FAIL" -ExitCode $checkoutCode -RemoteExists $remoteExists -LocalExists $localExists -Message "checkout 失败: $(($checkoutOutput | Out-String).Trim())"
            }
            return ConvertTo-WorkerResult -Status "OK" -RemoteExists $remoteExists -LocalExists $true -MetadataRef $metadataRef -Message "checkout OK -> $TargetBranch"
        }

        if (-not $remoteExists) {
            return ConvertTo-WorkerResult -Status "SKIP" -RemoteExists $false -LocalExists $localExists -MetadataRef $metadataRef -Message "远端 $RemoteName 无分支 $TargetBranch，跳过 pull"
        }
        if ($UseDryRun) {
            return ConvertTo-WorkerResult -Status "DRYRUN" -RemoteExists $true -LocalExists $localExists -MetadataRef $metadataRef -Message "计划: git pull --no-rebase $RemoteName $TargetBranch"
        }

        $pullOutput = & git pull --no-rebase $RemoteName $TargetBranch 2>&1
        $pullCode = $LASTEXITCODE
        if ($pullCode -ne 0) {
            return ConvertTo-WorkerResult -Status "FAIL" -ExitCode $pullCode -RemoteExists $true -LocalExists $localExists -MetadataRef $metadataRef -Message "pull 失败: $(($pullOutput | Out-String).Trim())"
        }
        $brief = ($pullOutput | Out-String).Trim().Split("`n")[0]
        return ConvertTo-WorkerResult -Status "OK" -RemoteExists $true -LocalExists $localExists -MetadataRef $metadataRef -Message "pull OK$(if ($brief) { " | $brief" })"
    } finally {
        Pop-Location
    }
}

function ConvertTo-LocalResult {
    param([object]$Repo, [string]$Operation, [string]$Status, [string]$Message)
    [PSCustomObject]@{
        RepoPath = $Repo.Path; RepoName = $Repo.Name; Operation = $Operation; TargetBranch = $Repo.TargetBranch
        Status = $Status; ExitCode = 0; Message = $Message
        RemoteExists = $null; LocalExists = $null; MetadataRef = $null
    }
}

function Register-OperationResult {
    param([object]$Repo, [object]$Result)
    if ($Result.Operation -eq "checkout") { $Repo.CheckoutStatus = $Result.Status }
    if ($Result.Operation -eq "pull") { $Repo.PullStatus = $Result.Status }
    if ($Result.MetadataRef) { $Repo.MetadataRef = $Result.MetadataRef }

    switch ($Result.Status) {
        "OK" { $script:Stats.Success++; Write-Status -RepoName $Repo.Name -Message $Result.Message -Level "OK" }
        "DRYRUN" { $script:Stats.Planned++; Write-Status -RepoName $Repo.Name -Message $Result.Message -Level "PLAN" }
        "SKIP" { $script:Stats.Skipped++; Write-Status -RepoName $Repo.Name -Message $Result.Message -Level "SKIP" }
        "DEPENDENCY" { $script:Stats.DependencyFailed++; Write-Status -RepoName $Repo.Name -Message $Result.Message -Level "DEPENDENCY" }
        default {
            $script:Stats.Failed++
            Write-Status -RepoName $Repo.Name -Message $Result.Message -Level "FAIL"
            $script:FailedRepos.Add([PSCustomObject]@{ Name = $Repo.Name; Path = $Repo.RelativePath; Step = $Result.Operation; Message = $Result.Message })
        }
    }
}

function Invoke-RepositoryBatch {
    param([object[]]$Repos, [ValidateSet("checkout", "pull")][string]$Operation, [switch]$AssumeTargetCheckedOut)
    if ($Repos.Count -eq 0) { return @() }

    $threadJobAvailable = [bool](Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)
    $useParallel = $Parallel -and $Repos.Count -gt 1 -and $threadJobAvailable
    if ($Parallel -and -not $threadJobAvailable -and $Repos.Count -gt 1) {
        Write-Status -RepoName "SYSTEM" -Message "Start-ThreadJob 不可用，回退到顺序执行" -Level "WARN"
    }

    $results = [System.Collections.Generic.List[object]]::new()
    if (-not $useParallel) {
        foreach ($repo in $Repos) {
            $result = & $script:OperationWorker $repo.Path $repo.Name $Operation $repo.TargetBranch $Remote $RetryCount $RetryDelaySeconds $DryRun.IsPresent $AssumeTargetCheckedOut.IsPresent
            $results.Add($result)
        }
        return $results.ToArray()
    }

    $batchSize = [Math]::Max(1, $ThrottleLimit)
    for ($i = 0; $i -lt $Repos.Count; $i += $batchSize) {
        $end = [Math]::Min($i + $batchSize - 1, $Repos.Count - 1)
        $batch = @($Repos[$i..$end])
        $jobEntries = [System.Collections.Generic.List[object]]::new()
        foreach ($repo in $batch) {
            $job = Start-ThreadJob -Name "$Operation::$($repo.Name)" -ScriptBlock $script:OperationWorker -ArgumentList $repo.Path, $repo.Name, $Operation, $repo.TargetBranch, $Remote, $RetryCount, $RetryDelaySeconds, $DryRun.IsPresent, $AssumeTargetCheckedOut.IsPresent
            $jobEntries.Add([PSCustomObject]@{ Job = $job; Repo = $repo })
        }

        Wait-Job -Job @($jobEntries | ForEach-Object { $_.Job }) | Out-Null
        foreach ($entry in $jobEntries) {
            $received = @(Receive-Job -Job $entry.Job -ErrorAction SilentlyContinue)
            Remove-Job -Job $entry.Job -Force | Out-Null
            $result = $received | Where-Object { $_.PSObject.Properties["Status"] } | Select-Object -Last 1
            if ($null -eq $result) {
                $result = ConvertTo-LocalResult -Repo $entry.Repo -Operation $Operation -Status "FAIL" -Message "并行任务未返回有效结果"
            }
            $results.Add($result)
        }
    }
    return $results.ToArray()
}

function Invoke-AndRegisterBatch {
    param([object[]]$Repos, [ValidateSet("checkout", "pull")][string]$Operation, [switch]$AssumeTargetCheckedOut)
    $results = @(Invoke-RepositoryBatch -Repos $Repos -Operation $Operation -AssumeTargetCheckedOut:$AssumeTargetCheckedOut)
    foreach ($result in $results) {
        $repo = Get-RepoPlan -Path $result.RepoPath
        if ($null -ne $repo) { Register-OperationResult -Repo $repo -Result $result }
    }
}

function Test-CheckoutSucceeded {
    param([object]$Repo)
    return $Repo.CheckoutStatus -in @("OK", "DRYRUN")
}

function Test-PullAllowsChild {
    param([object]$Repo)
    return $Repo.PullStatus -in @("OK", "DRYRUN", "SKIP")
}

function Get-RepoChildReadiness {
    param([object]$Repo)
    switch ($Mode) {
        "CheckoutOnly" { Test-CheckoutSucceeded -Repo $Repo }
        "PullOnly" { $Repo.PullStatus -in @("OK", "DRYRUN") }
        default { (Test-CheckoutSucceeded -Repo $Repo) -and (Test-PullAllowsChild -Repo $Repo) }
    }
}

function Register-DependencyFailure {
    param([object]$Repo, [string]$Message)
    $operation = if ($Mode -eq "PullOnly") { "pull" } else { "checkout" }
    Register-OperationResult -Repo $Repo -Result (ConvertTo-LocalResult -Repo $Repo -Operation $operation -Status "DEPENDENCY" -Message $Message)
    $Repo.ReadyForChildren = $false
}

function Invoke-RepoGroup {
    param([object[]]$Repos, [string]$SectionName)
    if ($Repos.Count -eq 0) { return }
    Write-Section $SectionName

    $readyRepos = [System.Collections.Generic.List[object]]::new()
    foreach ($repo in $Repos) {
        if ($repo.Type -eq "Submodule") {
            $parent = Get-RepoPlan -Path $repo.ParentPath
            if ($null -eq $parent -or -not $parent.ReadyForChildren) {
                Register-DependencyFailure -Repo $repo -Message "父仓库未成功完成，跳过此仓库及其后代"
                continue
            }

            $resolution = Get-TargetBranch -Repo $repo
            if (-not $resolution.Valid) {
                Register-DependencyFailure -Repo $repo -Message $resolution.Message
                continue
            }
            if (-not $resolution.Registered) {
                Register-OperationResult -Repo $repo -Result (ConvertTo-LocalResult -Repo $repo -Operation "resolve" -Status "SKIP" -Message "$($resolution.Message)，跳过已从目标版本移除的子模块")
                $repo.ReadyForChildren = $false
                continue
            }

            $repo.TargetBranch = $resolution.Branch
            $repo.BranchSource = $resolution.Source
            $repo.SubmoduleName = $resolution.SubmoduleName
            $script:BranchStats[$resolution.Source]++
        } else {
            $repo.TargetBranch = $Branch
            $repo.BranchSource = "Parameter"
            $script:BranchStats.Parameter++
        }
        $readyRepos.Add($repo)
    }

    $ready = @($readyRepos)
    if ($ready.Count -eq 0) { return }
    if ($Mode -in @("All", "CheckoutOnly")) {
        Invoke-AndRegisterBatch -Repos $ready -Operation "checkout"
    }
    if ($Mode -in @("All", "PullOnly")) {
        $pullRepos = if ($Mode -eq "All") { @($ready | Where-Object { Test-CheckoutSucceeded -Repo $_ }) } else { $ready }
        if ($Mode -eq "All") {
            foreach ($repo in @($ready | Where-Object { -not (Test-CheckoutSucceeded -Repo $_) })) {
                Register-OperationResult -Repo $repo -Result (ConvertTo-LocalResult -Repo $repo -Operation "pull" -Status "DEPENDENCY" -Message "checkout 未成功，禁止继续 pull")
            }
        }
        Invoke-AndRegisterBatch -Repos $pullRepos -Operation "pull" -AssumeTargetCheckedOut:($DryRun -and $Mode -eq "All")
    }
    foreach ($repo in $ready) { $repo.ReadyForChildren = Get-RepoChildReadiness -Repo $repo }
}

$startTime = Get-Date
Write-Banner "Git 安全批量 Checkout & Pull"
Write-Host "  主目录:       $MainDir" -ForegroundColor White
Write-Host "  主目标分支:   $Branch" -ForegroundColor Yellow
Write-Host "  远程:         $Remote" -ForegroundColor White
Write-Host "  模式:         $Mode" -ForegroundColor White
Write-Host "  重试:         $RetryCount 次，间隔 ${RetryDelaySeconds}s（仅远端检查/fetch）" -ForegroundColor White
Write-Host "  并行执行:     $(if ($Parallel) { "是，批次大小 $ThrottleLimit" } else { "否" })" -ForegroundColor White
Write-Host "  仅处理子模块: $(if ($SubmodulesOnly) { "是" } else { "否" })" -ForegroundColor White
Write-Host "  最大深度:     $MaxDepth" -ForegroundColor White
Write-Host "  DryRun:        $(if ($DryRun) { "是（允许 fetch，不修改 HEAD/工作树）" } else { "否" })" -ForegroundColor $(if ($DryRun) { "Magenta" } else { "White" })
Write-Host "  日志文件:     $logFile" -ForegroundColor DarkGray
Write-GitBatchLog -Message "开始执行 | 主目录=$MainDir | 分支=$Branch | 远程=$Remote | 模式=$Mode | 并行=$($Parallel.IsPresent) | DryRun=$($DryRun.IsPresent)"

Write-Section "扫描与分类 Git 仓库"
$allRepos = @(Find-GitRepo -Path $MainDir)
if ($allRepos.Count -eq 0) {
    Write-Host "  未找到任何 Git 仓库。" -ForegroundColor Red
    Write-GitBatchLog -Message "未找到 Git 仓库" -Level "ERROR"
    if (-not $NoPause) { Read-Host "按 Enter 退出" }
    exit 2
}

Initialize-RepoPlan -Repos $allRepos
$activeRepos = [System.Collections.Generic.List[object]]::new()
foreach ($repo in $allRepos) {
    if (Test-ShouldExclude -RelativePath $repo.RelativePath) {
        $repo.Excluded = $true
        $script:Stats.Skipped++
        Write-Status -RepoName $repo.Name -Message "排除: $($repo.RelativePath)" -Level "SKIP"
        continue
    }
    if ($SubmodulesOnly -and $repo.Type -eq "Standalone") {
        $repo.Excluded = $true
        $script:Stats.Skipped++
        Write-Status -RepoName $repo.Name -Message "非主仓库且非子模块，-SubmodulesOnly 跳过" -Level "SKIP"
        continue
    }
    $activeRepos.Add($repo)
}

$mainRepo = @($activeRepos | Where-Object { $_.Type -eq "Main" } | Select-Object -First 1)
$submoduleCount = @($activeRepos | Where-Object { $_.Type -eq "Submodule" }).Count
$standaloneCount = @($activeRepos | Where-Object { $_.Type -eq "Standalone" }).Count
Write-Host "  发现 $($allRepos.Count) 个仓库：主仓库 $($mainRepo.Count)，子模块 $submoduleCount，独立仓库 $standaloneCount；实际处理 $($activeRepos.Count) 个" -ForegroundColor Gray
Write-GitBatchLog -Message "发现=$($allRepos.Count) | 主仓库=$($mainRepo.Count) | 子模块=$submoduleCount | 独立仓库=$standaloneCount | 处理=$($activeRepos.Count)"

if ($mainRepo.Count -gt 0) {
    $mainRepo[0].TargetBranch = $Branch
    $mainRepo[0].BranchSource = "Parameter"
    Invoke-RepoGroup -Repos @($mainRepo[0]) -SectionName "主仓库 -> $Branch"
} else {
    Write-Status -RepoName "SYSTEM" -Message "MainDir 本身不是 Git 仓库，将以扫描容器模式处理其余仓库" -Level "WARN"
}

$childGroups = @($activeRepos | Where-Object { $_.Type -ne "Main" } | Group-Object -Property Depth | Sort-Object { [int]$_.Name })
foreach ($group in $childGroups) {
    $levelRepos = @($group.Group)
    Invoke-RepoGroup -Repos $levelRepos -SectionName "第 $($group.Name) 层仓库（$($levelRepos.Count) 个）"
}

$elapsed = (Get-Date) - $startTime
$elapsedStr = "{0:hh\:mm\:ss}" -f $elapsed
Write-Host ""
Write-Host ('═' * $script:TotalWidth) -ForegroundColor Cyan
Write-Host ""
Write-Host "  汇总报告" -ForegroundColor Cyan
Write-Host "    成功:       $($script:Stats.Success)" -ForegroundColor Green
Write-Host "    计划:       $($script:Stats.Planned)" -ForegroundColor Magenta
Write-Host "    失败:       $($script:Stats.Failed)" -ForegroundColor $(if ($script:Stats.Failed -gt 0) { "Red" } else { "Green" })
Write-Host "    跳过:       $($script:Stats.Skipped)" -ForegroundColor Yellow
Write-Host "    依赖跳过:   $($script:Stats.DependencyFailed)" -ForegroundColor DarkYellow
Write-Host "    耗时:       $elapsedStr" -ForegroundColor White
Write-Host ""
Write-Host "  分支来源" -ForegroundColor Cyan
Write-Host "    参数:       $($script:BranchStats.Parameter)" -ForegroundColor Gray
Write-Host "    .gitmodules: $($script:BranchStats.Gitmodules)" -ForegroundColor Gray
Write-Host "    branch = .: $($script:BranchStats.Inherited)" -ForegroundColor Gray
Write-Host "    回退参数:   $($script:BranchStats.Fallback)" -ForegroundColor Gray

if ($script:FailedRepos.Count -gt 0) {
    Write-Host ""
    Write-Host "  失败仓库:" -ForegroundColor Red
    foreach ($failed in $script:FailedRepos) {
        Write-Host "    X $($failed.Step.PadRight(10)) $($failed.Path)" -ForegroundColor Red
        Write-Detail $failed.Message
    }
    $failedSummary = [string]::Join(', ', @($script:FailedRepos | ForEach-Object { "$($_.Step):$($_.Path)" }))
    Write-GitBatchLog -Message "失败仓库: $failedSummary" -Level "ERROR"
}

$exitCode = if ($script:Stats.Failed -gt 0 -or $script:Stats.DependencyFailed -gt 0) { 1 } else { 0 }
Write-Host ""
Write-Host "  日志: $logFile" -ForegroundColor DarkGray
Write-Host ('═' * $script:TotalWidth) -ForegroundColor Cyan
Write-GitBatchLog -Message "执行完毕 | 成功=$($script:Stats.Success) | 计划=$($script:Stats.Planned) | 失败=$($script:Stats.Failed) | 跳过=$($script:Stats.Skipped) | 依赖跳过=$($script:Stats.DependencyFailed) | 耗时=$elapsedStr"
if (-not $NoPause) { Read-Host "按 Enter 退出" }
exit $exitCode
