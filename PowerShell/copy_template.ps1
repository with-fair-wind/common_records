### 通用文件/目录复制脚本 v2.2
### 功能：支持单个或多个复制任务，支持多目标，智能跳过相同文件，支持白名单和黑名单
### 特性：
###   - Files 参数（白名单）：可选，指定要复制的文件/目录列表
###   - Exclude 参数（黑名单）：可选，指定要排除的文件/目录列表
###   - Mode 参数：Sync（保留额外文件）或 Mirror（删除多余文件）
###   - 智能跳过：自动对比文件大小和修改时间，跳过相同文件
###   - 三种模式：完整目录 / 白名单（只复制指定） / 黑名单（排除指定）
$ErrorActionPreference = 'Stop'

function Copy-FilesWithProgress {
    <#
    .SYNOPSIS
        带进度显示的文件/目录复制函数
    
    .PARAMETER SourceDir
        源目录路径
    
    .PARAMETER DestDirs
        目标目录路径数组（支持多个目标）
    
    .PARAMETER Mode
        复制模式：
        - 'Sync': 同步模式（保留目标目录中的额外文件）
        - 'Mirror': 镜像模式（删除目标目录中多余的文件）
        
        说明：
        - Files 参数（白名单）：只复制指定的文件/目录
        - Exclude 参数（黑名单）：复制整个目录，但排除指定的文件/目录
        - 无参数：复制整个源目录
        - Mode 控制是否删除多余文件（Sync=保留，Mirror=删除）
    
    .PARAMETER Files
        要复制的文件列表（可选，白名单模式）
        - 如果指定：只复制列表中的文件/目录
        - 支持文件名、相对路径、子目录
        - 不能与 Exclude 同时使用
    
    .PARAMETER Exclude
        要排除的文件列表（可选，黑名单模式）
        - 如果指定：复制整个目录，但排除列表中的文件/目录
        - 支持文件名、相对路径、子目录
        - 不能与 Files 同时使用
    
    .PARAMETER Title
        任务标题
    
    .PARAMETER Enabled
        是否启用该任务
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir,
        
        [Parameter(Mandatory)]
        [string[]]$DestDirs,
        
        [ValidateSet('Mirror', 'Sync')]
        [string]$Mode = 'Sync',
        
        [string[]]$Files = @(),
        
        [string[]]$Exclude = @(),
        
        [string]$Title = '复制任务',
        
        [bool]$Enabled = $true
    )
    
    # 参数验证
    if ($Files.Count -gt 0 -and $Exclude.Count -gt 0) {
        throw "Files 和 Exclude 参数不能同时使用！请选择白名单模式（Files）或黑名单模式（Exclude）"
    }
    
    if (-not $Enabled) {
        Write-Host ("# 跳过任务: {0} (已禁用)" -f $Title) -ForegroundColor DarkYellow
        return [PSCustomObject]@{
            Title        = $Title
            Success      = 0
            Errors       = 0
            Skipped      = $true
            CopiedSizeMB = 0
        }
    }
    
    Write-Host ""
    Write-Host ("# {0}" -f $Title) -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    Write-Host "源目录:   " -ForegroundColor Yellow -NoNewline
    Write-Host $SourceDir -ForegroundColor White
    Write-Host "目标目录列表:" -ForegroundColor Yellow
    foreach ($dest in $DestDirs) {
        Write-Host "  - $dest" -ForegroundColor White
    }
    Write-Host "复制模式: " -ForegroundColor Yellow -NoNewline
    
    if ($Files.Count -gt 0) {
        $scopeText = "指定文件 (白名单: $($Files.Count) 项)"
    }
    elseif ($Exclude.Count -gt 0) {
        $scopeText = "完整目录排除 (黑名单: $($Exclude.Count) 项)"
    }
    else {
        $scopeText = "完整目录"
    }
    
    $deleteText = if ($Mode -eq 'Mirror') { "删除多余文件" } else { "保留额外文件" }
    $color = if ($Mode -eq 'Mirror') { "Magenta" } else { "Cyan" }
    
    Write-Host "$scopeText + $Mode ($deleteText)" -ForegroundColor $color
    
    # 显示详细的包含/排除列表
    if ($Files.Count -gt 0) {
        Write-Host "包含列表:" -ForegroundColor Yellow
        foreach ($file in $Files) {
            Write-Host "  + $file" -ForegroundColor Green
        }
    }
    elseif ($Exclude.Count -gt 0) {
        Write-Host "排除列表:" -ForegroundColor Yellow
        foreach ($file in $Exclude) {
            Write-Host "  - $file" -ForegroundColor Red
        }
    }
    
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    
    # 检查源目录
    if (-not (Test-Path -LiteralPath $SourceDir)) {
        throw "源目录不存在: $SourceDir"
    }
    
    # 创建所有目标目录
    foreach ($destDir in $DestDirs) {
        if (-not (Test-Path -LiteralPath $destDir)) {
            Write-Host "正在创建目标目录: $destDir" -ForegroundColor DarkYellow
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Write-Host "✓ 目标目录创建成功" -ForegroundColor Green
        }
    }
    
    Write-Host ""
    
    $startTime = Get-Date
    $copiedCount = 0
    $skippedCount = 0
    $errorCount = 0
    $copiedSize = 0
    
    # 根据模式确定要复制的文件
    if ($Files.Count -gt 0) {
        # ========== 白名单模式：只复制指定文件 ==========
        
        Write-Host "正在扫描源文件（白名单模式）..." -ForegroundColor Cyan
        
        # 预先收集所有文件信息，用于计算总数和进度
        $allFileItems = @()
        foreach ($file in $Files) {
            $relativePath = $file.Trim().TrimEnd('\', '/')
            $sourcePath = Join-Path -Path $SourceDir -ChildPath $relativePath
            
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                Write-Host "  ✗ 未找到: $relativePath" -ForegroundColor Red
                $errorCount += $DestDirs.Count
                continue
            }
            
            $sourceItem = Get-Item -LiteralPath $sourcePath -Force
            
            if ($sourceItem.PSIsContainer) {
                # 目录：展开所有子文件
                $dirFiles = Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force
                foreach ($dirFile in $dirFiles) {
                    $fileRelativePath = $dirFile.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
                    $allFileItems += [PSCustomObject]@{
                        SourcePath    = $dirFile.FullName
                        RelativePath  = $fileRelativePath
                        Size          = $dirFile.Length
                        LastWriteTime = $dirFile.LastWriteTime
                    }
                }
            }
            else {
                # 单个文件
                $allFileItems += [PSCustomObject]@{
                    SourcePath    = $sourcePath
                    RelativePath  = $relativePath
                    Size          = $sourceItem.Length
                    LastWriteTime = $sourceItem.LastWriteTime
                }
            }
        }
        
        $totalFiles = $allFileItems.Count
        $totalSize = ($allFileItems | Measure-Object -Property Size -Sum).Sum
        $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
        $totalTasks = $totalFiles * $DestDirs.Count
        
        Write-Host "✓ 扫描完成: $totalFiles 个文件, $totalSizeMB MB" -ForegroundColor Green
        Write-Host "目标数量: $($DestDirs.Count) 个" -ForegroundColor Gray
        Write-Host "总任务数: $totalTasks 次复制" -ForegroundColor Gray
        Write-Host ""
        Write-Host "开始复制..." -ForegroundColor Cyan
        
        $processedCount = 0
        foreach ($fileItem in $allFileItems) {
            $processedCount++
            $fileSizeKB = [math]::Round($fileItem.Size / 1KB, 2)
            
            foreach ($destDir in $DestDirs) {
                $destPath = Join-Path -Path $destDir -ChildPath $fileItem.RelativePath
                $destParent = Split-Path -Path $destPath -Parent
                
                if (-not (Test-Path -LiteralPath $destParent)) {
                    New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                }
                
                # 检查是否需要复制
                $needCopy = $true
                if (Test-Path -LiteralPath $destPath) {
                    $destFile = Get-Item -LiteralPath $destPath
                    if ($fileItem.Size -eq $destFile.Length -and 
                        $fileItem.LastWriteTime -eq $destFile.LastWriteTime) {
                        $needCopy = $false
                    }
                }
                
                if ($needCopy) {
                    try {
                        Copy-Item -LiteralPath $fileItem.SourcePath -Destination $destPath -Force -ErrorAction Stop
                        $copiedCount++
                        
                        # 只对第一个目标计入复制大小（避免重复计算）
                        if ($destDir -eq $DestDirs[0]) {
                            $copiedSize += $fileItem.Size
                        }
                        
                        $progress = [math]::Round($processedCount / $totalFiles * 100, 1)
                        
                        # 精简输出：只在最后一个目标时输出
                        if ($destDir -eq $DestDirs[-1]) {
                            Write-Host "[$progress%] ✓ " -ForegroundColor Green -NoNewline
                            Write-Host "$($fileItem.RelativePath) " -ForegroundColor Gray -NoNewline
                            if ($DestDirs.Count -gt 1) {
                                Write-Host "-> $($DestDirs.Count) 个目标 " -ForegroundColor DarkCyan -NoNewline
                            }
                            Write-Host "($fileSizeKB KB)" -ForegroundColor DarkGray
                        }
                    }
                    catch {
                        $errorCount++
                        $progress = [math]::Round($processedCount / $totalFiles * 100, 1)
                        Write-Host "[$progress%] ✗ " -ForegroundColor Red -NoNewline
                        Write-Host "$($fileItem.RelativePath) -> $destDir " -ForegroundColor Gray -NoNewline
                        Write-Host "[错误: $($_.Exception.Message)]" -ForegroundColor Red
                    }
                }
                else {
                    $skippedCount++
                }
            }
            
            # 每50个文件显示一次跳过进度
            if ($skippedCount % (50 * $DestDirs.Count) -eq 0 -and $skippedCount -gt 0) {
                $progress = [math]::Round($processedCount / $totalFiles * 100, 1)
                Write-Host "[$progress%] 已跳过 $skippedCount 个相同文件..." -ForegroundColor DarkGray
            }
        }
        
        # Files 模式的 Mirror 行为：删除目标目录中不在指定列表的文件
        if ($Mode -eq 'Mirror') {
            Write-Host ""
            Write-Host "检查目标目录中的多余文件（Mirror 模式）..." -ForegroundColor Cyan
            
            # 收集所有要保留的文件路径（源文件列表）
            $sourceFileSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($fileItem in $allFileItems) {
                [void]$sourceFileSet.Add($fileItem.RelativePath)
            }
            
            $deletedCount = 0
            foreach ($destDir in $DestDirs) {
                Write-Host "正在检查: $destDir" -ForegroundColor Gray
                
                if (-not (Test-Path -LiteralPath $destDir)) {
                    continue
                }
                
                $destFiles = Get-ChildItem -LiteralPath $destDir -Recurse -File -Force
                
                foreach ($destFile in $destFiles) {
                    $relativePath = $destFile.FullName.Substring($destDir.Length).TrimStart('\', '/')
                    
                    # 如果目标文件不在源文件列表中，删除它
                    if (-not $sourceFileSet.Contains($relativePath)) {
                        try {
                            Remove-Item -LiteralPath $destFile.FullName -Force -ErrorAction Stop
                            $deletedCount++
                            Write-Host "  ✗ 已删除多余文件: " -ForegroundColor Red -NoNewline
                            Write-Host $relativePath -ForegroundColor Gray
                        }
                        catch {
                            Write-Host "  ✗ 删除失败: " -ForegroundColor Red -NoNewline
                            Write-Host "$relativePath [错误: $($_.Exception.Message)]" -ForegroundColor Red
                        }
                    }
                }
                
                # 清理空目录
                $emptyDirs = Get-ChildItem -LiteralPath $destDir -Recurse -Directory -Force | Sort-Object -Property FullName -Descending
                foreach ($dir in $emptyDirs) {
                    if ((Get-ChildItem -LiteralPath $dir.FullName -Force).Count -eq 0) {
                        try {
                            Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction Stop
                        }
                        catch {
                            # 忽略删除目录的错误
                        }
                    }
                }
            }
            
            if ($deletedCount -gt 0) {
                Write-Host "✓ 已删除 $deletedCount 个多余文件" -ForegroundColor Yellow
            }
            else {
                Write-Host "✓ 未发现多余文件" -ForegroundColor Green
            }
        }
    }
    else {
        # ========== 完整目录模式（可能带黑名单） ==========
        if ($Exclude.Count -gt 0) {
            Write-Host "正在扫描源目录（黑名单模式）..." -ForegroundColor Cyan
        }
        else {
            Write-Host "正在扫描源目录..." -ForegroundColor Cyan
        }
        
        $allFiles = Get-ChildItem -LiteralPath $SourceDir -Recurse -File -Force
        
        # 如果是黑名单模式，需要构建排除集合
        $excludeSet = $null
        if ($Exclude.Count -gt 0) {
            $excludeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            
            # 展开排除列表（支持目录和文件）
            foreach ($excludeItem in $Exclude) {
                $excludePath = $excludeItem.Trim().TrimEnd('\', '/')
                $excludeFullPath = Join-Path -Path $SourceDir -ChildPath $excludePath
                
                if (Test-Path -LiteralPath $excludeFullPath) {
                    $item = Get-Item -LiteralPath $excludeFullPath -Force
                    
                    if ($item.PSIsContainer) {
                        # 目录：排除该目录下的所有文件
                        $excludeDirFiles = Get-ChildItem -LiteralPath $excludeFullPath -Recurse -File -Force
                        foreach ($file in $excludeDirFiles) {
                            $relPath = $file.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
                            [void]$excludeSet.Add($relPath)
                        }
                    }
                    else {
                        # 文件：直接排除
                        [void]$excludeSet.Add($excludePath)
                    }
                }
            }
            
            # 过滤掉被排除的文件
            $allFiles = $allFiles | Where-Object {
                $relativePath = $_.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
                -not $excludeSet.Contains($relativePath)
            }
            
            Write-Host "✓ 已排除 $($excludeSet.Count) 个文件" -ForegroundColor Yellow
        }
        
        $totalFiles = $allFiles.Count
        $totalSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
        $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
        $totalTasks = $totalFiles * $DestDirs.Count
        
        Write-Host "✓ 扫描完成: $totalFiles 个文件, $totalSizeMB MB" -ForegroundColor Green
        Write-Host "目标数量: $($DestDirs.Count) 个" -ForegroundColor Gray
        Write-Host "总任务数: $totalTasks 次复制" -ForegroundColor Gray
        Write-Host ""
        Write-Host "开始复制..." -ForegroundColor Cyan
        
        $processedCount = 0
        foreach ($file in $allFiles) {
            $processedCount++
            $relativePath = $file.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
            $fileSizeKB = [math]::Round($file.Length / 1KB, 2)
            
            foreach ($destDir in $DestDirs) {
                $destPath = Join-Path -Path $destDir -ChildPath $relativePath
                $destParent = Split-Path -Path $destPath -Parent
                
                if (-not (Test-Path -LiteralPath $destParent)) {
                    New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                }
                
                # 检查是否需要复制
                $needCopy = $true
                if (Test-Path -LiteralPath $destPath) {
                    $destFile = Get-Item -LiteralPath $destPath
                    if ($file.Length -eq $destFile.Length -and 
                        $file.LastWriteTime -eq $destFile.LastWriteTime) {
                        $needCopy = $false
                    }
                }
                
                if ($needCopy) {
                    try {
                        Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force -ErrorAction Stop
                        $copiedCount++
                        
                        # 只对第一个目标计入复制大小（避免重复计算）
                        if ($destDir -eq $DestDirs[0]) {
                            $copiedSize += $file.Length
                        }
                        
                        $progress = [math]::Round($processedCount / $totalFiles * 100, 1)
                        
                        # 精简输出：只显示第一个目标，其他目标用简写
                        if ($DestDirs.Count -gt 1 -and $destDir -ne $DestDirs[0]) {
                            # 不输出，在最后一个目标时统一输出
                            if ($destDir -eq $DestDirs[-1]) {
                                Write-Host "[$progress%] ✓ " -ForegroundColor Green -NoNewline
                                Write-Host "$relativePath " -ForegroundColor Gray -NoNewline
                                Write-Host "-> $($DestDirs.Count) 个目标 " -ForegroundColor DarkCyan -NoNewline
                                Write-Host "($fileSizeKB KB)" -ForegroundColor DarkGray
                            }
                        }
                        else {
                            Write-Host "[$progress%] ✓ " -ForegroundColor Green -NoNewline
                            Write-Host "$relativePath " -ForegroundColor Gray -NoNewline
                            if ($DestDirs.Count -eq 1) {
                                Write-Host "($fileSizeKB KB)" -ForegroundColor DarkGray
                            }
                            else {
                                Write-Host "-> $($DestDirs.Count) 个目标 " -ForegroundColor DarkCyan -NoNewline
                                Write-Host "($fileSizeKB KB)" -ForegroundColor DarkGray
                            }
                        }
                    }
                    catch {
                        $errorCount++
                        $progress = [math]::Round($processedCount / $totalFiles * 100, 1)
                        Write-Host "[$progress%] ✗ " -ForegroundColor Red -NoNewline
                        Write-Host "$relativePath -> $destDir " -ForegroundColor Gray -NoNewline
                        Write-Host "[错误: $($_.Exception.Message)]" -ForegroundColor Red
                    }
                }
                else {
                    $skippedCount++
                }
            }
            
            # 每50个文件显示一次跳过进度
            if ($skippedCount % (50 * $DestDirs.Count) -eq 0 -and $skippedCount -gt 0) {
                $progress = [math]::Round($processedCount / $totalFiles * 100, 1)
                Write-Host "[$progress%] 已跳过 $skippedCount 个相同文件..." -ForegroundColor DarkGray
            }
        }
        
        # 镜像模式：删除多余文件
        if ($Mode -eq 'Mirror') {
            Write-Host ""
            Write-Host "检查目标目录中的多余文件..." -ForegroundColor Cyan
            
            $deletedCount = 0
            foreach ($destDir in $DestDirs) {
                Write-Host "正在检查: $destDir" -ForegroundColor Gray
                
                if (-not (Test-Path -LiteralPath $destDir)) {
                    continue
                }
                
                $destFiles = Get-ChildItem -LiteralPath $destDir -Recurse -File -Force
                
                foreach ($destFile in $destFiles) {
                    $relativePath = $destFile.FullName.Substring($destDir.Length).TrimStart('\', '/')
                    $sourcePath = Join-Path -Path $SourceDir -ChildPath $relativePath
                    
                    $shouldDelete = $false
                    $deleteReason = ""
                    
                    # 检查1：源目录中不存在
                    if (-not (Test-Path -LiteralPath $sourcePath)) {
                        $shouldDelete = $true
                        $deleteReason = "源不存在"
                    }
                    # 检查2：在排除列表中（黑名单模式）
                    elseif ($excludeSet -and $excludeSet.Contains($relativePath)) {
                        $shouldDelete = $true
                        $deleteReason = "在排除列表"
                    }
                    
                    if ($shouldDelete) {
                        try {
                            Remove-Item -LiteralPath $destFile.FullName -Force -ErrorAction Stop
                            $deletedCount++
                            Write-Host "  ✗ 已删除多余文件 ($deleteReason): " -ForegroundColor Red -NoNewline
                            Write-Host $relativePath -ForegroundColor Gray
                        }
                        catch {
                            Write-Host "  ✗ 删除失败: " -ForegroundColor Red -NoNewline
                            Write-Host "$relativePath [错误: $($_.Exception.Message)]" -ForegroundColor Red
                        }
                    }
                }
                
                # 清理空目录
                $emptyDirs = Get-ChildItem -LiteralPath $destDir -Recurse -Directory -Force | Sort-Object -Property FullName -Descending
                foreach ($dir in $emptyDirs) {
                    if ((Get-ChildItem -LiteralPath $dir.FullName -Force).Count -eq 0) {
                        try {
                            Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction Stop
                        }
                        catch {
                            # 忽略删除目录的错误
                        }
                    }
                }
            }
            
            if ($deletedCount -gt 0) {
                Write-Host "✓ 已删除 $deletedCount 个多余文件" -ForegroundColor Yellow
            }
            else {
                Write-Host "✓ 未发现多余文件" -ForegroundColor Green
            }
        }
    }
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $copiedSizeMB = [math]::Round($copiedSize / 1MB, 2)
    
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    Write-Host "任务完成！" -ForegroundColor Cyan
    Write-Host "  已复制: " -ForegroundColor Green -NoNewline
    Write-Host "$copiedCount 个文件 ($copiedSizeMB MB)" -ForegroundColor White
    
    if ($skippedCount -gt 0) {
        Write-Host "  已跳过: " -ForegroundColor Yellow -NoNewline
        Write-Host "$skippedCount 个文件 (文件相同)" -ForegroundColor White
    }
    
    if ($errorCount -gt 0) {
        Write-Host "  失败: " -ForegroundColor Red -NoNewline
        Write-Host "$errorCount 个文件" -ForegroundColor White
    }
    
    Write-Host "  耗时: " -ForegroundColor Gray -NoNewline
    Write-Host ("{0:mm}分{0:ss}秒" -f $duration) -ForegroundColor White
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    
    if ($errorCount -eq 0) {
        Write-Host "✓ 所有操作成功完成！(^_^)" -ForegroundColor Green
    }
    else {
        Write-Host "⚠ 部分文件处理失败，请检查错误信息 (╥﹏╥)" -ForegroundColor Yellow
    }
    
    return [PSCustomObject]@{
        Title        = $Title
        Success      = $copiedCount
        Skipped      = $skippedCount
        Errors       = $errorCount
        CopiedSizeMB = $copiedSizeMB
        Duration     = $duration
    }
}

# ==================== 任务配置 ====================
# 在这里配置你的复制任务

$tasks = @(
    # 示例1：复制整个目录到单个目标（镜像模式）
    @{
        Title     = 'VS2026离线安装包同步'
        Enabled   = $false  # 设为 $true 启用该任务
        SourceDir = 'E:\code\pwsh\VS2026Offline'
        DestDirs  = @(
            'D:\install\VS2026Offline'
        )
        Mode      = 'Mirror'  # 镜像模式，会删除目标目录中多余的文件
    }
    
    # 示例2：复制整个目录到多个目标（同步模式）
    @{
        Title     = '文档多处备份'
        Enabled   = $false
        SourceDir = 'D:\Documents'
        DestDirs  = @(
            'E:\Backup\Documents',
            'F:\Archive\Documents',
            '\\NAS\Backup\Documents'
        )
        Mode      = 'Sync'  # 同步模式，不删除目标目录中的额外文件
    }
    
    # 示例3：复制指定文件列表到单个目标
    @{
        Title     = '编译输出文件复制'
        Enabled   = $false
        SourceDir = 'D:\project\bin\Release'
        DestDirs  = @(
            'D:\deploy\app'
        )
        Mode      = 'Sync'  # 同步模式：只复制指定文件，保留其他文件
        Files     = @(
            'app.exe',
            'config.json',
            'lib\module1.dll',
            'lib\module2.dll',
            'data\'  # 复制整个 data 子目录
        )
    }
    
    # 示例4：复制指定文件列表到多个目标（最常用场景）
    @{
        Title     = 'ZRX文件多环境部署'
        Enabled   = $false
        SourceDir = 'D:\work\code\output\Debug_Zrx2026_x64\arx'
        DestDirs  = @(
            'D:\work\env\SketchDesign\trunk\package\64位环境\ZW2026-OEM\arx',
            'D:\work\code\电缆设计-配电设计\arx',
            'D:\Program Files\EAP2026\arx'
        )
        Mode      = 'Sync'  # 同步模式：只复制指定文件，保留其他文件
        Files     = @(
            'GZPDM.zrx',
            'BcBPDS.zrx',
            'byqpmsj.zrx',
            'BPDS_DrawWire.zrx'
        )
    }
    
    # 示例5：指定文件列表 + 镜像模式（白名单：只保留指定的文件）
    @{
        Title     = 'Scoop 应用精简镜像（白名单）'
        Enabled   = $false
        SourceDir = 'D:\scoop\apps'
        DestDirs  = @(
            'X:\scoop\apps'
        )
        Mode      = 'Mirror'  # 镜像模式：只保留指定的应用，删除其他应用
        Files     = @(
            'scoop',
            'cmake',
            'ninja',
            'llvm',
            'msys2',
            'vscode',
            'cursor'
        )
    }
    
    # 示例6：排除列表 + 同步模式（黑名单：复制整个目录，排除指定的文件）
    @{
        Title     = 'Scoop 备份（排除大型应用）'
        Enabled   = $false
        SourceDir = 'D:\scoop\apps'
        DestDirs  = @(
            'X:\scoop\apps'
        )
        Mode      = 'Sync'  # 同步模式：保留额外文件
        Exclude   = @(
            'llvm',         # 排除 LLVM（体积大）
            'nodejs',       # 排除 Node.js
            'python',       # 排除 Python
            'visualstudio'  # 排除 Visual Studio
        )
    }
    
    # 示例7：排除列表 + 镜像模式（黑名单 + 删除排除的文件）
    @{
        Title     = '项目代码同步（排除编译产物和缓存）'
        Enabled   = $false
        SourceDir = 'D:\project\myapp'
        DestDirs  = @(
            'E:\backup\myapp'
        )
        Mode      = 'Mirror'  # 镜像模式：删除排除的文件和多余文件
        Exclude   = @(
            'bin\',         # 排除编译输出目录
            'obj\',         # 排除中间文件目录
            'node_modules\',# 排除 npm 依赖
            '.vs\',         # 排除 Visual Studio 缓存
            '.git\'         # 排除 Git 仓库
        )
    }

    @{
        Title     = '拷贝VS2022离线安装包'
        Enabled   = $true  # 设为 $true 启用该任务
        SourceDir = 'F:\VS2022Offline'
        DestDirs  = @(
            'D:\install\VS2022Offline'
        )
        Mode      = 'Mirror'  # 同步模式，保留额外文件
    }
)

# ==================== 执行任务 ====================

try {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              通用文件复制脚本 v2.2                           ║" -ForegroundColor Cyan
    Write-Host "║   多目标 | 智能跳过 | 白名单/黑名单 | Mirror/Sync 模式     ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    if ($tasks.Count -eq 0) {
        Write-Host "⚠ 没有配置任何任务！" -ForegroundColor Yellow
        Write-Host "请编辑脚本中的 `$tasks 数组，添加你的复制任务。" -ForegroundColor Gray
        Write-Host ""
        Write-Host "按任意键退出..." -ForegroundColor DarkGray
        Read-Host | Out-Null
        exit 0
    }
    
    $enabledTasks = $tasks | Where-Object { $_.Enabled -eq $true }
    
    if ($enabledTasks.Count -eq 0) {
        Write-Host "⚠ 所有任务都已禁用！" -ForegroundColor Yellow
        Write-Host "请将需要执行的任务的 Enabled 设为 `$true" -ForegroundColor Gray
        Write-Host ""
        Write-Host "按任意键退出..." -ForegroundColor DarkGray
        Read-Host | Out-Null
        exit 0
    }
    
    Write-Host "共有 $($tasks.Count) 个任务，其中 $($enabledTasks.Count) 个已启用" -ForegroundColor Gray
    Write-Host ""
    
    $results = @()
    foreach ($task in $tasks) {
        $results += Copy-FilesWithProgress @task
    }
    
    # 输出汇总
    if ($results.Count -gt 1) {
        $enabledResults = $results | Where-Object { -not $_.Skipped }
        if ($enabledResults.Count -gt 0) {
            Write-Host ""
            Write-Host ("═" * 80) -ForegroundColor Cyan
            Write-Host "所有任务汇总统计" -ForegroundColor Cyan
            Write-Host ("═" * 80) -ForegroundColor Cyan
            
            $totalSuccess = ($enabledResults | Measure-Object -Property Success -Sum).Sum
            $totalSkipped = ($enabledResults | Measure-Object -Property Skipped -Sum).Sum
            $totalErrors = ($enabledResults | Measure-Object -Property Errors -Sum).Sum
            $totalSizeMB = ($enabledResults | Measure-Object -Property CopiedSizeMB -Sum).Sum
            $totalSizeMB = [math]::Round($totalSizeMB, 2)
            
            Write-Host "  已复制: " -ForegroundColor Green -NoNewline
            Write-Host "$totalSuccess 个文件 ($totalSizeMB MB)" -ForegroundColor White
            
            if ($totalSkipped -gt 0) {
                Write-Host "  已跳过: " -ForegroundColor Yellow -NoNewline
                Write-Host "$totalSkipped 个文件" -ForegroundColor White
            }
            
            if ($totalErrors -gt 0) {
                Write-Host "  失败: " -ForegroundColor Red -NoNewline
                Write-Host "$totalErrors 个文件" -ForegroundColor White
            }
            
            Write-Host ("═" * 80) -ForegroundColor Cyan
            
            if ($totalErrors -eq 0) {
                Write-Host "✓ 所有任务成功完成！\\(^o^)/" -ForegroundColor Green
            }
            else {
                Write-Host "⚠ 部分任务存在错误，请查看详细日志" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host ""
    Write-Host "全部任务处理完成，按任意键退出..." -ForegroundColor DarkGray
    Read-Host | Out-Null
    
    exit 0
}
catch {
    Write-Host ""
    Write-Host ("═" * 80) -ForegroundColor Red
    Write-Host "发生严重错误！" -ForegroundColor Red
    Write-Host ("═" * 80) -ForegroundColor Red
    Write-Host "错误信息: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "错误位置: 第 $($_.InvocationInfo.ScriptLineNumber) 行" -ForegroundColor Red
    Write-Host ("═" * 80) -ForegroundColor Red
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor DarkGray
    Read-Host | Out-Null
    
    exit 1
}
