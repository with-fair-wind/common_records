# ========= 基础配置 =========
$oldEmail = "yangyukai@zwcad.com"
$newEmail = "921232958@qq.com"
$basePath = "D:\Project_All\rewrite_git_email_project"
$githubUser = "with-fair-wind"

# 为每个仓库指定它的主分支
$repos = @(
    @{ Name = "Template"; Branch = "master" },
    @{ Name = "algorithm"; Branch = "main" },
    @{ Name = "with-fair-wind"; Branch = "master" }
)

function Invoke-Push($refSpec) {
    $result = git push origin $refSpec --force-with-lease 2>&1
    if ($LASTEXITCODE -ne 0 -and $result -match "stale info") {
        Write-Warning "⚠ 远端分支已变化，改用 --force 强制推送"
        git push origin $refSpec --force
    }
    else {
        Write-Host "✔ 推送成功：$refSpec"
    }
}

foreach ($repoInfo in $repos) {
    $repo = $repoInfo.Name
    $defaultBranch = $repoInfo.Branch
    $repoPath = Join-Path $basePath $repo
    $remoteUrl = "git@github.com:$githubUser/$repo.git"

    Write-Host "`n▶ 正在处理仓库: $repo （主分支: $defaultBranch）" -ForegroundColor Cyan

    # ====== 如果本地目录不存在，则先 clone ======
    if (!(Test-Path $repoPath)) {
        Write-Host "⚠ 本地目录不存在，正在 clone $repo ..." -ForegroundColor Yellow
        git clone $remoteUrl $repoPath
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "❌ Clone 失败，跳过 $repo"
            continue
        }
        Write-Host "✔ Clone 完成：$repoPath"
    }

    Push-Location $repoPath

    # 确保 checkout 到指定的主分支
    git fetch origin
    git checkout $defaultBranch

    # ========== 生成 mailmap ==========
    $mailmapText = "kk <$newEmail> <$oldEmail>"
    $mailmapFile = "mailmap.txt"
    Set-Content -Path $mailmapFile -Value $mailmapText -Encoding UTF8
    Write-Host "✔ 已生成 mailmap.txt 内容: $mailmapText"

    # ========== 改写历史 ==========
    git filter-repo --mailmap $mailmapFile --force

    # ========== 恢复 origin（防止 clone 后没有 remote 配置） ==========
    if (-not (git remote)) {
        git remote add origin $remoteUrl
        Write-Host "✔ 已恢复远程：origin -> $remoteUrl"
    }
    else {
        Write-Host "✔ 远程 origin 已存在，跳过恢复"
    }

    # ========== 推送（自动处理 stale info） ==========
    Invoke-Push $defaultBranch
    Invoke-Push "--tags"

    # ========== 清理 ==========
    Remove-Item -Force $mailmapFile

    Pop-Location
    Write-Host "✅ 仓库 $repo 已处理完毕！"
}
