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
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

$directRepos = @(
    "IMModeling",
    "AppFx",
    "Basics",
    "DBX",
    "ExternalCmds",
    "Graphics",
    "Interactions",
    "IntfNet",
    "isp",
    "Managed",
    "Map",
    "Out",
    "PlatServices",
    "PointCloudServices",
    "Ribbon",
    "RuntimeX",
    "ZwImageCore"
)

$nestedRepoGroups = @(
    "AMEP",
    "BIM",
    "InternalCmds",
    "Resources",
    "SDKInc"
)

if (-not (Test-Path -Path $MainDir -PathType Container)) {
    throw "Main directory not found: $MainDir"
}

if (-not (Test-Path -Path $LogDir -PathType Container)) {
    New-Item -Path $LogDir -ItemType Directory | Out-Null
}

$timeTag = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $LogDir "bimdevelop_checkoutpull_$timeTag.log"

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "OK")]
        [string]$Level = "INFO"
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $script:logFile -Value $line
    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "OK"    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
}

function Get-RepoTargets {
    param([Parameter(Mandatory = $true)][string]$Root)

    $targets = New-Object System.Collections.Generic.List[string]
    $targets.Add($Root)

    foreach ($dir in Get-ChildItem -Path $Root -Directory) {
        if ($directRepos -contains $dir.Name) {
            $targets.Add($dir.FullName)
            continue
        }

        if ($nestedRepoGroups -contains $dir.Name) {
            foreach ($sub in Get-ChildItem -Path $dir.FullName -Directory) {
                $targets.Add($sub.FullName)
            }
        }
    }

    return $targets
}

function Invoke-GitStep {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][ValidateSet("checkout", "pull")][string]$Step
    )

    $maxAttempts = [Math]::Max(1, $RetryCount + 1)
    $gitArgs = if ($Step -eq "checkout") {
        @("checkout", $Branch)
    }
    else {
        @("pull", "--progress", "-v", "--no-rebase", $Remote, $Branch)
    }

    if ($DryRun) {
        Write-Log -Level "INFO" -Message "DryRun: [$RepoPath] git $($gitArgs -join ' ')"
        return [pscustomobject]@{
            RepoPath = $RepoPath
            Step = $Step
            Success = $true
            ExitCode = 0
            Attempts = 0
            Command = "git $($gitArgs -join ' ')"
        }
    }

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Push-Location $RepoPath
            $output = & git @gitArgs 2>&1
            $code = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        if ($code -eq 0) {
            Write-Log -Level "OK" -Message "[$Step] success: $RepoPath (attempt $attempt/$maxAttempts)"
            return [pscustomobject]@{
                RepoPath = $RepoPath
                Step = $Step
                Success = $true
                ExitCode = 0
                Attempts = $attempt
                Command = "git $($gitArgs -join ' ')"
                Output = ($output | Out-String).Trim()
            }
        }

        Write-Log -Level "WARN" -Message "[$Step] failed: $RepoPath (attempt $attempt/$maxAttempts, exit=$code)"
        if ($attempt -lt $maxAttempts) {
            Start-Sleep -Seconds $RetryDelaySeconds
        }
        else {
            return [pscustomobject]@{
                RepoPath = $RepoPath
                Step = $Step
                Success = $false
                ExitCode = $code
                Attempts = $attempt
                Command = "git $($gitArgs -join ' ')"
                Output = ($output | Out-String).Trim()
            }
        }
    }
}

function Invoke-GitStepParallel {
    param(
        [Parameter(Mandatory = $true)][string[]]$Targets,
        [Parameter(Mandatory = $true)][ValidateSet("checkout", "pull")][string]$Step
    )

    if (-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)) {
        Write-Log -Level "WARN" -Message "Start-ThreadJob is unavailable, fallback to sequential mode."
        return $Targets | ForEach-Object { Invoke-GitStep -RepoPath $_ -Step $Step }
    }

    $results = New-Object System.Collections.Generic.List[object]
    $batchSize = [Math]::Max(1, $ThrottleLimit)

    for ($i = 0; $i -lt $Targets.Count; $i += $batchSize) {
        $end = [Math]::Min($i + $batchSize - 1, $Targets.Count - 1)
        $batch = $Targets[$i..$end]

        $jobs = foreach ($repo in $batch) {
            Start-ThreadJob -Name "$Step::$repo" -ScriptBlock {
            param($RepoPath, $StepName, $BranchName, $RemoteName, $MaxRetry, $RetryDelay, $UseDryRun)

            $maxAttempts = [Math]::Max(1, $MaxRetry + 1)
            $gitArgs = if ($StepName -eq "checkout") {
                @("checkout", $BranchName)
            }
            else {
                @("pull", "--progress", "-v", "--no-rebase", $RemoteName, $BranchName)
            }

            if ($UseDryRun) {
                return [pscustomobject]@{
                    RepoPath = $RepoPath
                    Step = $StepName
                    Success = $true
                    ExitCode = 0
                    Attempts = 0
                    Command = "git $($gitArgs -join ' ')"
                    Output = "DryRun"
                }
            }

            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try {
                    Push-Location $RepoPath
                    $output = & git @gitArgs 2>&1
                    $code = $LASTEXITCODE
                }
                finally {
                    Pop-Location
                }

                if ($code -eq 0) {
                    return [pscustomobject]@{
                        RepoPath = $RepoPath
                        Step = $StepName
                        Success = $true
                        ExitCode = 0
                        Attempts = $attempt
                        Command = "git $($gitArgs -join ' ')"
                        Output = ($output | Out-String).Trim()
                    }
                }

                if ($attempt -lt $maxAttempts) {
                    Start-Sleep -Seconds $RetryDelay
                }
                else {
                    return [pscustomobject]@{
                        RepoPath = $RepoPath
                        Step = $StepName
                        Success = $false
                        ExitCode = $code
                        Attempts = $attempt
                        Command = "git $($gitArgs -join ' ')"
                        Output = ($output | Out-String).Trim()
                    }
                }
            }
            } -ArgumentList $repo, $Step, $Branch, $Remote, $RetryCount, $RetryDelaySeconds, $DryRun.IsPresent
        }

        Wait-Job -Job $jobs | Out-Null
        $batchResults = Receive-Job -Job $jobs
        Remove-Job -Job $jobs | Out-Null

        foreach ($r in $batchResults) {
            if ($r.Success) {
                Write-Log -Level "OK" -Message "[$($r.Step)] success: $($r.RepoPath) (attempt $($r.Attempts))"
            }
            else {
                Write-Log -Level "ERROR" -Message "[$($r.Step)] failed: $($r.RepoPath) exit=$($r.ExitCode)"
                if ($r.Output) {
                    Write-Log -Level "ERROR" -Message $r.Output
                }
            }
            $results.Add($r)
        }
    }

    return $results
}

$targets = Get-RepoTargets -Root $MainDir
Write-Log -Message "Target repositories: $($targets.Count)"
Write-Log -Message "Mode=$Mode, Branch=$Branch, Remote=$Remote, RetryCount=$RetryCount, Parallel=$($Parallel.IsPresent), DryRun=$($DryRun.IsPresent)"

$allResults = New-Object System.Collections.Generic.List[object]

if ($Mode -in @("All", "CheckoutOnly")) {
    Write-Log -Message "========== Begin checkout =========="
    $checkoutResults = if ($Parallel) {
        Invoke-GitStepParallel -Targets $targets -Step "checkout"
    }
    else {
        $targets | ForEach-Object { Invoke-GitStep -RepoPath $_ -Step "checkout" }
    }
    foreach ($r in $checkoutResults) { $allResults.Add($r) }
}

if ($Mode -in @("All", "PullOnly")) {
    Write-Log -Message "========== Begin pull =========="
    $pullResults = if ($Parallel) {
        Invoke-GitStepParallel -Targets $targets -Step "pull"
    }
    else {
        $targets | ForEach-Object { Invoke-GitStep -RepoPath $_ -Step "pull" }
    }
    foreach ($r in $pullResults) { $allResults.Add($r) }
}

$failed = @($allResults | Where-Object { -not $_.Success })
$succeeded = @($allResults | Where-Object { $_.Success })

Write-Log -Message "========== Summary =========="
Write-Log -Level "INFO" -Message "Success count: $($succeeded.Count)"
Write-Log -Level "INFO" -Message "Failed count: $($failed.Count)"
Write-Log -Level "INFO" -Message "Log file: $logFile"

if ($failed.Count -gt 0) {
    Write-Log -Level "ERROR" -Message "Failed repositories:"
    foreach ($item in $failed) {
        Write-Log -Level "ERROR" -Message "step=$($item.Step), repo=$($item.RepoPath), exit=$($item.ExitCode), attempts=$($item.Attempts)"
    }
    $global:LASTEXITCODE = 1
}
else {
    $global:LASTEXITCODE = 0
}

if (-not $NoPause) {
    Read-Host "Press Enter to exit"
}
