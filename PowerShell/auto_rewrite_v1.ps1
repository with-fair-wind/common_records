# ========= 基础配置 =========
$oldEmail = "yangyukai@zwcad.com"
$newEmail = "921232958@qq.com"
$repos = @("algorithm")  # 要处理的仓库名
$basePath = "D:\Project_All\Cpp_Project"
$githubUser = "with-fair-wind"  # GitHub 用户名

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

foreach ($repo in $repos) {
    Write-Host "`n▶ 正在处理仓库: $repo ..." -ForegroundColor Cyan
    $repoPath = Join-Path $basePath $repo

    if (!(Test-Path $repoPath)) {
        Write-Warning "⚠ 仓库目录不存在：$repoPath，跳过"
        continue
    }

    Push-Location $repoPath

    # ========== 生成 mailmap ==========
    $mailmapText = "kk <$newEmail> <$oldEmail>"
    $mailmapFile = "mailmap.txt"
    Set-Content -Path $mailmapFile -Value $mailmapText -Encoding UTF8
    Write-Host "✔ 已生成 mailmap.txt 内容: $mailmapText"

    # ========== 改写历史 ==========
    git filter-repo --mailmap $mailmapFile --force

    # ========== 恢复 origin ==========
    $remoteName = "origin"
    $remoteUrl = "git@github.com:$githubUser/$repo.git"

    if (-not (git remote)) {
        git remote add $remoteName $remoteUrl
        Write-Host "✔ 已恢复远程：$remoteName -> $remoteUrl"
    }
    else {
        Write-Host "✔ 远程 $remoteName 已存在，跳过恢复"
    }

    # ========== 推送（自动处理 stale info） ==========
    Invoke-Push "main"
    Invoke-Push "--tags"

    # ========== 清理 ==========
    Remove-Item -Force $mailmapFile

    Pop-Location
    Write-Host "✅ 仓库 $repo 已处理完毕！"
}
