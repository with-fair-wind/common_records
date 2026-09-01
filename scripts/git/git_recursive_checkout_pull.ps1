param(
    [string]$MainDir = (Join-Path (Get-Location) "main"),
    [string]$Branch = "developbim",
    [string]$Remote = "origin",
    [ValidateSet("All", "CheckoutOnly", "PullOnly")]
    [string]$Mode = "All",
    [int]$RetryCount = 2,
    [int]$RetryDelaySeconds = 2,
    [switch]$Parallel,
    [int]$ThrottleLimit = 6,
    [switch]$DryRun,
    [string]$LogDir = (Join-Path $PSScriptRoot "logs"),
    [string[]]$ExcludePatterns = @(),
    [int]$MaxDepth = 5,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

$defaultExcludePatterns = @(
    "BIM\ZwBm",
    "BIM\BmDb"
)

if (-not (Test-Path -Path $MainDir -PathType Container)) {
    throw "主目录不存在: $MainDir"
}

if (-not (Test-Path -Path $LogDir -PathType Container)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

$timeTag = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $LogDir "git_checkout_pull_$timeTag.log"

# ─────────────────────────────────────────────────────────────────────────────
# 美化输出工具
# ─────────────────────────────────────────────────────────────────────────────

$script:TotalWidth = 72
$script:Stats = @{ Success = 0; Failed = 0; Skipped = 0 }
$script:FailedRepos = [System.Collections.Generic.List[object]]::new()

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "OK")]
        [string]$Level = "INFO"
    )
    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Message
    Add-Content -Path $script:logFile -Value $line -ErrorAction SilentlyContinue
}

function Write-Banner {
    param([string]$Text)
    $innerWidth = $script:TotalWidth - 2
    $pad = [Math]::Max(0, $innerWidth - $Text.Length - 2)
    $left = [Math]::Floor($pad / 2)
    $right = $pad - $left
    $top = "╔$('═' * $innerWidth)╗"
    $mid = "║$(' ' * $left) $Text $(' ' * $right)║"
    $bot = "╚$('═' * $innerWidth)╝"
    Write-Host ""
    Write-Host $top -ForegroundColor Cyan
    Write-Host $mid -ForegroundColor Cyan
    Write-Host $bot -ForegroundColor Cyan
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
        [ValidateSet("OK", "FAIL", "SKIP", "INFO", "WARN")]
        [string]$Level = "INFO"
    )
    $icon = switch ($Level) {
        "OK"   { "[+]" }
        "FAIL" { "[X]" }
        "SKIP" { "[-]" }
        "WARN" { "[!]" }
        default { "[*]" }
    }
    $color = switch ($Level) {
        "OK"   { "Green" }
        "FAIL" { "Red" }
        "SKIP" { "DarkYellow" }
        "WARN" { "Yellow" }
        default { "White" }
    }
    $nameDisplay = if ($RepoName.Length -gt 28) { $RepoName.Substring(0, 25) + "..." } else { $RepoName }
    $prefix = "$icon $($nameDisplay.PadRight(28))"
    Write-Host $prefix -ForegroundColor $color -NoNewline
    Write-Host " $Message" -ForegroundColor Gray

    $logLevel = switch ($Level) { "OK" { "OK" } "FAIL" { "ERROR" } "SKIP" { "WARN" } "WARN" { "WARN" } default { "INFO" } }
    Write-Log -Message "$RepoName | $Message" -Level $logLevel
}

function Write-Detail {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

# ─────────────────────────────────────────────────────────────────────────────
# 核心功能
# ─────────────────────────────────────────────────────────────────────────────

function Find-GitRepos {
    param(
        [string]$Path,
        [int]$CurrentDepth = 0
    )

    if ($CurrentDepth -gt $MaxDepth) { return }

    $gitDir = Join-Path $Path ".git"
    $isGitRepo = Test-Path $gitDir

    if ($isGitRepo) {
        [PSCustomObject]@{
            Path         = $Path
            Name         = Split-Path $Path -Leaf
            RelativePath = Get-RelativePath -BasePath $MainDir -TargetPath $Path
        }
    }

    $children = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue
    foreach ($child in $children) {
        if ($child.Name -in @("node_modules", ".git", "__pycache__", ".vs", ".idea")) { continue }
        Find-GitRepos -Path $child.FullName -CurrentDepth ($CurrentDepth + 1)
    }
}

function Get-RelativePath {
    param([string]$BasePath, [string]$TargetPath)
    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $target = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\', '/')
    if ($target.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $target.Substring($base.Length).TrimStart('\', '/')
        if (-not $rel) { return "." }
        return $rel
    }
    return $target
}

function Test-ShouldExclude {
    param([string]$RelativePath)

    # 顶层仓库（MainDir 本身）的相对路径为 "."，不是目录名，任何目录名规则都匹配不到它；
    # 这里额外用 MainDir 的目录名参与匹配，方便直接用目录名排除顶层仓库
    $matchTargets = @($RelativePath)
    if ($RelativePath -eq ".") {
        $topLeaf = Split-Path $MainDir -Leaf
        if ($topLeaf -and $matchTargets -notcontains $topLeaf) { $matchTargets += $topLeaf }
    }

    $allPatterns = $defaultExcludePatterns + $ExcludePatterns
    foreach ($pattern in $allPatterns) {
        if (-not $pattern) { continue }
        $normalized = $pattern.Trim().Replace('/', '\')
        foreach ($target in $matchTargets) {
            if ($target -like "*$normalized*") { return $true }
        }
    }
    return $false
}

function Invoke-GitOperation {
    param(
        [string]$RepoPath,
        [string]$RepoName,
        [ValidateSet("checkout", "pull")]
        [string]$Operation
    )

    if ($DryRun) {
        if ($Operation -eq "checkout") {
            Write-Status -RepoName $RepoName -Message "DRY RUN: git fetch $Remote; git checkout $Branch (本地无此分支时自动 -b --track $Remote/$Branch)" -Level "INFO"
        } else {
            Write-Status -RepoName $RepoName -Message "DRY RUN: git pull --no-rebase $Remote $Branch" -Level "INFO"
        }
        return $true
    }

    if ($Operation -eq "checkout") {
        # 先 fetch 保证远程引用最新；本地无此分支则从远程建立跟踪分支，否则直接切换
        Push-Location $RepoPath
        try {
            $fetchOut = & git fetch $Remote --quiet 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log -Message "$RepoName | fetch $Remote 失败（继续尝试 checkout）: $(($fetchOut | Out-String).Trim())" -Level "WARN"
            }
            & git show-ref --verify --quiet "refs/heads/$Branch"
            $localExists = ($LASTEXITCODE -eq 0)
        } finally {
            Pop-Location
        }
        $gitArgs = if ($localExists) {
            @("checkout", $Branch)
        } else {
            @("checkout", "-b", $Branch, "--track", "$Remote/$Branch")
        }
    } else {
        $gitArgs = @("pull", "--no-rebase", $Remote, $Branch)
    }

    $maxAttempts = $RetryCount + 1
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Push-Location $RepoPath
            $output = & git @gitArgs 2>&1
            $code = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        if ($code -eq 0) {
            $brief = ($output | Out-String).Trim().Split("`n")[0]
            if ($brief.Length -gt 50) { $brief = $brief.Substring(0, 50) + "..." }
            Write-Status -RepoName $RepoName -Message "$Operation OK$(if($brief){" | $brief"})" -Level "OK"
            return $true
        }

        if ($attempt -lt $maxAttempts) {
            Write-Status -RepoName $RepoName -Message "$Operation 失败 (第 $attempt 次)，${RetryDelaySeconds}s 后重试..." -Level "WARN"
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    $errMsg = ($output | Out-String).Trim().Split("`n") | Select-Object -First 2
    Write-Status -RepoName $RepoName -Message "$Operation 失败 (exit=$code, 共尝试 $maxAttempts 次)" -Level "FAIL"
    foreach ($line in $errMsg) {
        Write-Detail $line
    }
    return $false
}

function Invoke-GitOperationParallel {
    param(
        [object[]]$Repos,
        [ValidateSet("checkout", "pull")]
        [string]$Operation
    )

    if (-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)) {
        Write-Status -RepoName "SYSTEM" -Message "Start-ThreadJob 不可用，回退到顺序模式" -Level "WARN"
        return (Invoke-GitOperationSequential -Repos $Repos -Operation $Operation)
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $batchSize = [Math]::Max(1, $ThrottleLimit)

    for ($i = 0; $i -lt $Repos.Count; $i += $batchSize) {
        $end = [Math]::Min($i + $batchSize - 1, $Repos.Count - 1)
        $batch = $Repos[$i..$end]

        $jobs = foreach ($repo in $batch) {
            Start-ThreadJob -Name "$Operation::$($repo.Name)" -ScriptBlock {
                param($RepoPath, $RepoName, $Op, $BranchName, $RemoteName, $MaxRetry, $RetryDelay, $UseDryRun)

                if ($UseDryRun) {
                    return [PSCustomObject]@{
                        RepoName = $RepoName; RepoPath = $RepoPath
                        Operation = $Op; Success = $true; ExitCode = 0
                        Attempts = 0; Output = "DRY RUN"
                    }
                }

                $fetchWarn = $null
                if ($Op -eq "checkout") {
                    # 先 fetch 保证远程引用最新；本地无此分支则从远程建立跟踪分支，否则直接切换
                    Push-Location $RepoPath
                    try {
                        $fetchOut = & git fetch $RemoteName --quiet 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            $fetchWarn = "fetch $RemoteName 失败（继续尝试 checkout）: $(($fetchOut | Out-String).Trim())"
                        }
                        & git show-ref --verify --quiet "refs/heads/$BranchName"
                        $localExists = ($LASTEXITCODE -eq 0)
                    } finally {
                        Pop-Location
                    }
                    $gitArgs = if ($localExists) {
                        @("checkout", $BranchName)
                    } else {
                        @("checkout", "-b", $BranchName, "--track", "$RemoteName/$BranchName")
                    }
                } else {
                    $gitArgs = @("pull", "--no-rebase", $RemoteName, $BranchName)
                }

                $maxAttempts = $MaxRetry + 1
                for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                    try {
                        Push-Location $RepoPath
                        $output = & git @gitArgs 2>&1
                        $code = $LASTEXITCODE
                    } finally {
                        Pop-Location
                    }

                    if ($code -eq 0) {
                        return [PSCustomObject]@{
                            RepoName = $RepoName; RepoPath = $RepoPath
                            Operation = $Op; Success = $true; ExitCode = 0
                            Attempts = $attempt; Output = ($output | Out-String).Trim()
                            FetchWarning = $fetchWarn
                        }
                    }

                    if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds $RetryDelay }
                }

                return [PSCustomObject]@{
                    RepoName = $RepoName; RepoPath = $RepoPath
                    Operation = $Op; Success = $false; ExitCode = $code
                    Attempts = $maxAttempts; Output = ($output | Out-String).Trim()
                    FetchWarning = $fetchWarn
                }
            } -ArgumentList $repo.Path, $repo.Name, $Operation, $Branch, $Remote, $RetryCount, $RetryDelaySeconds, $DryRun.IsPresent
        }

        Wait-Job -Job $jobs | Out-Null
        $batchResults = Receive-Job -Job $jobs
        Remove-Job -Job $jobs -Force | Out-Null

        foreach ($r in $batchResults) {
            if ($r.FetchWarning) {
                Write-Log -Message "$($r.RepoName) | $($r.FetchWarning)" -Level "WARN"
            }
            if ($r.Success) {
                $brief = $r.Output.Split("`n")[0]
                if ($brief.Length -gt 50) { $brief = $brief.Substring(0, 50) + "..." }
                Write-Status -RepoName $r.RepoName -Message "$($r.Operation) OK$(if($brief -and $brief -ne 'DRY RUN'){" | $brief"})" -Level "OK"
                $script:Stats.Success++
            } else {
                Write-Status -RepoName $r.RepoName -Message "$($r.Operation) 失败 (exit=$($r.ExitCode))" -Level "FAIL"
                if ($r.Output) {
                    $r.Output.Split("`n") | Select-Object -First 2 | ForEach-Object { Write-Detail $_ }
                }
                $script:Stats.Failed++
                $script:FailedRepos.Add([PSCustomObject]@{ Name = $r.RepoName; Path = $r.RepoPath; Step = $r.Operation })
            }
            $results.Add($r)
        }
    }

    return $results
}

function Invoke-GitOperationSequential {
    param(
        [object[]]$Repos,
        [ValidateSet("checkout", "pull")]
        [string]$Operation
    )

    $counter = 0
    $total = $Repos.Count
    foreach ($repo in $Repos) {
        $counter++
        Write-Host "  ($counter/$total) " -NoNewline -ForegroundColor DarkGray
        $success = Invoke-GitOperation -RepoPath $repo.Path -RepoName $repo.Name -Operation $Operation
        if ($success) {
            $script:Stats.Success++
        } else {
            $script:Stats.Failed++
            $script:FailedRepos.Add([PSCustomObject]@{ Name = $repo.Name; Path = $repo.RelativePath; Step = $Operation })
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 主流程
# ─────────────────────────────────────────────────────────────────────────────

$startTime = Get-Date

Write-Banner "Git 批量 Checkout & Pull"

Write-Host "  主目录:     " -NoNewline -ForegroundColor DarkGray
Write-Host $MainDir -ForegroundColor White
Write-Host "  目标分支:   " -NoNewline -ForegroundColor DarkGray
Write-Host $Branch -ForegroundColor Yellow
Write-Host "  远程:       " -NoNewline -ForegroundColor DarkGray
Write-Host $Remote -ForegroundColor White
Write-Host "  模式:       " -NoNewline -ForegroundColor DarkGray
Write-Host $Mode -ForegroundColor White
Write-Host "  重试次数:   " -NoNewline -ForegroundColor DarkGray
Write-Host $RetryCount -ForegroundColor White
Write-Host "  重试间隔:   " -NoNewline -ForegroundColor DarkGray
Write-Host "${RetryDelaySeconds}s" -ForegroundColor White
Write-Host "  并行执行:   " -NoNewline -ForegroundColor DarkGray
Write-Host $(if ($Parallel) { "是 (批次大小: $ThrottleLimit)" } else { "否" }) -ForegroundColor White
Write-Host "  最大深度:   " -NoNewline -ForegroundColor DarkGray
Write-Host $MaxDepth -ForegroundColor White
Write-Host "  日志文件:   " -NoNewline -ForegroundColor DarkGray
Write-Host $logFile -ForegroundColor DarkGray
if ($DryRun) {
    Write-Host "  模拟运行:   " -NoNewline -ForegroundColor DarkGray
    Write-Host "是 (不执行实际 git 命令)" -ForegroundColor Magenta
}
Write-Host ""

Write-Log -Message "开始执行 | 主目录=$MainDir | 分支=$Branch | 远程=$Remote | 模式=$Mode | 并行=$($Parallel.IsPresent) | DryRun=$($DryRun.IsPresent)"

# 扫描仓库
Write-Section "扫描 Git 仓库"
$allRepos = @(Find-GitRepos -Path $MainDir)

if ($allRepos.Count -eq 0) {
    Write-Host "  未找到任何 Git 仓库！请检查主目录路径。" -ForegroundColor Red
    Write-Log -Message "未找到 Git 仓库" -Level "ERROR"
    if (-not $NoPause) { Read-Host "按 Enter 退出" }
    exit 1
}

# 过滤排除项
$repos = [System.Collections.Generic.List[object]]::new()
$excluded = [System.Collections.Generic.List[object]]::new()

foreach ($repo in $allRepos) {
    if (Test-ShouldExclude -RelativePath $repo.RelativePath) {
        $excluded.Add($repo)
        $script:Stats.Skipped++
    } else {
        $repos.Add($repo)
    }
}

Write-Host ""
Write-Host "  发现 " -NoNewline -ForegroundColor DarkGray
Write-Host "$($allRepos.Count)" -NoNewline -ForegroundColor Green
Write-Host " 个 Git 仓库，排除 " -NoNewline -ForegroundColor DarkGray
Write-Host "$($excluded.Count)" -NoNewline -ForegroundColor Yellow
Write-Host " 个，将处理 " -NoNewline -ForegroundColor DarkGray
Write-Host "$($repos.Count)" -NoNewline -ForegroundColor Green
Write-Host " 个" -ForegroundColor DarkGray

Write-Log -Message "发现 $($allRepos.Count) 个仓库，排除 $($excluded.Count) 个，处理 $($repos.Count) 个"

if ($excluded.Count -gt 0) {
    Write-Host ""
    foreach ($ex in $excluded) {
        Write-Status -RepoName $ex.Name -Message "排除: $($ex.RelativePath)" -Level "SKIP"
    }
}

# 执行 Checkout
if ($Mode -in @("All", "CheckoutOnly")) {
    Write-Section "Checkout -> $Branch ($($repos.Count) 个仓库)"
    Write-Log -Message "开始 checkout -> $Branch"

    if ($Parallel) {
        Invoke-GitOperationParallel -Repos $repos -Operation "checkout" | Out-Null
    } else {
        Invoke-GitOperationSequential -Repos $repos -Operation "checkout"
    }
}

# 执行 Pull
if ($Mode -in @("All", "PullOnly")) {
    Write-Section "Pull $Remote/$Branch ($($repos.Count) 个仓库)"
    Write-Log -Message "开始 pull $Remote/$Branch"

    if ($Parallel) {
        Invoke-GitOperationParallel -Repos $repos -Operation "pull" | Out-Null
    } else {
        Invoke-GitOperationSequential -Repos $repos -Operation "pull"
    }
}

# 汇总报告
$elapsed = (Get-Date) - $startTime
$elapsedStr = "{0:mm\:ss}" -f $elapsed

Write-Host ""
Write-Host ('═' * $script:TotalWidth) -ForegroundColor Cyan
Write-Host ""
Write-Host "  汇总报告" -ForegroundColor Cyan
Write-Host ""
Write-Host "    成功:   " -NoNewline -ForegroundColor DarkGray
Write-Host "$($script:Stats.Success)" -ForegroundColor Green
Write-Host "    失败:   " -NoNewline -ForegroundColor DarkGray
$failColor = if ($script:Stats.Failed -gt 0) { "Red" } else { "Green" }
Write-Host "$($script:Stats.Failed)" -ForegroundColor $failColor
Write-Host "    跳过:   " -NoNewline -ForegroundColor DarkGray
Write-Host "$($script:Stats.Skipped)" -ForegroundColor Yellow
Write-Host "    耗时:   " -NoNewline -ForegroundColor DarkGray
Write-Host $elapsedStr -ForegroundColor White

if ($script:FailedRepos.Count -gt 0) {
    Write-Host ""
    Write-Host "  失败仓库:" -ForegroundColor Red
    Write-Host "  $('-' * 50)" -ForegroundColor DarkGray
    foreach ($f in $script:FailedRepos) {
        Write-Host "    X " -NoNewline -ForegroundColor Red
        Write-Host "$($f.Step.PadRight(10))" -NoNewline -ForegroundColor DarkRed
        Write-Host " $($f.Path)" -ForegroundColor Red
    }
    Write-Log -Message "失败仓库: $($script:FailedRepos | ForEach-Object { "$($_.Step):$($_.Path)" } | Join-String -Separator ', ')" -Level "ERROR"
    $global:LASTEXITCODE = 1
} else {
    Write-Host ""
    Write-Host "  所有操作均已成功完成！" -ForegroundColor Green
    Write-Log -Message "全部成功完成" -Level "OK"
    $global:LASTEXITCODE = 0
}

Write-Host ""
Write-Host "  日志: $logFile" -ForegroundColor DarkGray
Write-Host ""
Write-Host ('═' * $script:TotalWidth) -ForegroundColor Cyan
Write-Host ""

Write-Log -Message "执行完毕 | 成功=$($script:Stats.Success) | 失败=$($script:Stats.Failed) | 跳过=$($script:Stats.Skipped) | 耗时=$elapsedStr"

if (-not $NoPause) {
    Read-Host "按 Enter 退出"
}
