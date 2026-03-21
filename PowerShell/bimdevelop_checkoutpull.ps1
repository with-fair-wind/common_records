param(
    [string]$MainDir = (Join-Path (Get-Location) "main"),
    [string]$Branch = "developbim",
    [string]$Remote = "origin",
    [switch]$NoPause
)

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

function Invoke-InRepo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if (-not (Test-Path -Path $RepoPath -PathType Container)) {
        Write-Warning "Skip missing directory: $RepoPath"
        return
    }

    Push-Location $RepoPath
    try {
        & $Action
    }
    finally {
        Pop-Location
    }
}

function Invoke-Checkout {
    param([Parameter(Mandatory = $true)][string]$RepoPath)

    Invoke-InRepo -RepoPath $RepoPath -Action {
        Write-Host "checkout -> $(Get-Location)"
        git checkout $Branch
    }
}

function Invoke-Pull {
    param([Parameter(Mandatory = $true)][string]$RepoPath)

    Invoke-InRepo -RepoPath $RepoPath -Action {
        Write-Host "pull -> $(Get-Location)"
        git pull --progress -v --no-rebase $Remote $Branch
    }
}

if (-not (Test-Path -Path $MainDir -PathType Container)) {
    throw "Main directory not found: $MainDir"
}

Write-Host "Begin checkout ZWBIM --------------------------------------------------------"

Push-Location $MainDir
try {
    git checkout $Branch

    foreach ($dir in Get-ChildItem -Directory) {
        Write-Host $dir.Name

        if ($directRepos -contains $dir.Name) {
            Invoke-Checkout -RepoPath $dir.FullName
            continue
        }

        if ($nestedRepoGroups -contains $dir.Name) {
            foreach ($item in Get-ChildItem -Path $dir.FullName) {
                if ($item.PSIsContainer) {
                    Invoke-Checkout -RepoPath $item.FullName
                }
                else {
                    Write-Host "$($dir.FullName)/$($item.Name) (not a directory)"
                }
            }
            continue
        }
    }

    Write-Host "Begin pull ZWBIM ------------------------------------------------------------"
    git pull --progress -v --no-rebase $Remote $Branch

    foreach ($dir in Get-ChildItem -Directory) {
        Write-Host $dir.Name

        if ($directRepos -contains $dir.Name) {
            Invoke-Pull -RepoPath $dir.FullName
            continue
        }

        if ($nestedRepoGroups -contains $dir.Name) {
            foreach ($item in Get-ChildItem -Path $dir.FullName) {
                if ($item.PSIsContainer) {
                    Invoke-Pull -RepoPath $item.FullName
                }
                else {
                    Write-Host "$($dir.FullName)/$($item.Name) (not a directory)"
                }
            }
            continue
        }
    }
}
finally {
    Pop-Location
}

Write-Host "End -------------------------------------------------------------------------"
if (-not $NoPause) {
    Read-Host "Press Enter to exit"
}
