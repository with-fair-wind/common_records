#Requires -Version 7.0
# 两个入口共用的清单、VSIX 校验及 VS Code CLI 调用；不直接执行同步。

function Get-NormalizedTargetPlatform {
    param([string]$TargetPlatform)
    if (-not $TargetPlatform -or $TargetPlatform -eq 'undefined') { return 'universal' }
    return $TargetPlatform.ToLowerInvariant()
}

function Assert-ExtensionIdentity {
    param([System.Collections.IDictionary]$Extension)
    if ($Extension.id -notmatch '^[a-z0-9][a-z0-9_-]*\.[a-z0-9][a-z0-9_-]*$' -or
        $Extension.version -notmatch '^\d+\.\d+\.\d+(?:-[0-9a-z.-]+)?(?:\+[0-9a-z.-]+)?$' -or
        $Extension.targetPlatform -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "扩展 ID、版本或平台无效：$($Extension.id)@$($Extension.version) [$($Extension.targetPlatform)]"
    }
}

function Write-BundleManifest {
    param([System.Collections.IDictionary]$Manifest, [string]$Path)
    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
        [IO.File]::Move($temporaryPath, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

function Assert-VsixPackage {
    param([string]$Path, [System.Collections.IDictionary]$Extension)
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $packageEntry = $archive.GetEntry('extension/package.json')
        $manifestEntry = $archive.GetEntry('extension.vsixmanifest')
        if (-not $packageEntry -or -not $manifestEntry) { throw "不是有效的 VS Code VSIX：$Path" }
        $reader = [IO.StreamReader]::new($packageEntry.Open())
        try { $package = $reader.ReadToEnd() | ConvertFrom-Json -AsHashtable }
        finally { $reader.Dispose() }

        $settings = [Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $stream = $manifestEntry.Open()
        try {
            $xmlReader = [Xml.XmlReader]::Create($stream, $settings)
            try {
                $document = [Xml.XmlDocument]::new()
                $document.XmlResolver = $null
                $document.Load($xmlReader)
            }
            finally { $xmlReader.Dispose() }
        }
        finally { $stream.Dispose() }
        $identity = $document.SelectSingleNode('/*[local-name()="PackageManifest"]/*[local-name()="Metadata"]/*[local-name()="Identity"]')
        if (-not $identity) { throw "VSIX 缺少 Identity：$Path" }
        $platform = Get-NormalizedTargetPlatform $identity.GetAttribute('TargetPlatform')
        $packageId = "$($package.publisher).$($package.name)"
        $manifestId = "$($identity.GetAttribute('Publisher')).$($identity.GetAttribute('Id'))"
        if ($packageId -ne $Extension.id -or $manifestId -ne $Extension.id -or
            $package.version -cne $Extension.version -or $identity.GetAttribute('Version') -cne $Extension.version -or
            $platform -ne $Extension.targetPlatform) {
            throw "VSIX 的 ID、版本或平台与清单不符：$Path"
        }
    }
    finally { $archive.Dispose() }
}

function Invoke-VSCodeCli {
    param([string]$CodeCmd, [string[]]$ArgumentList)
    # 显式检查退出码，避免调用者的原生命令错误策略影响失败汇总。
    $PSNativeCommandUseErrorActionPreference = $false
    $global:LASTEXITCODE = 0
    $output = @(& $CodeCmd @ArgumentList 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "VS Code 命令失败（退出码 $LASTEXITCODE）：$($output -join [Environment]::NewLine)"
    }
    return $output
}

function Get-VSCodeInstalledVersion {
    param([string]$CodeCmd, [string[]]$ScopeArguments)
    $installed = @{}
    $output = @(Invoke-VSCodeCli -CodeCmd $CodeCmd -ArgumentList (@('--list-extensions', '--show-versions') + $ScopeArguments))
    foreach ($line in $output) {
        if ([string]$line -match '^([a-z0-9][a-z0-9_-]*\.[a-z0-9][a-z0-9_-]*)@([^\s]+)$') {
            $installed[$Matches[1]] = $Matches[2]
        }
    }
    return $installed
}

function Assert-VsixDirectory {
    param([string]$Directory)
    if (-not [IO.Path]::IsPathFullyQualified($Directory)) { throw "VSIX 目录必须是绝对路径：$Directory" }
    $ancestor = [IO.Path]::GetFullPath($Directory)
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "VSIX 目录不能通过符号链接或目录联接重定向：$ancestor" }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
}

function Remove-UnreferencedVsixPackage {
    param([string]$Directory, [AllowEmptyCollection()][string[]]$KeepFileNames)
    Assert-VsixDirectory -Directory $Directory
    $fullDirectory = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    $keep = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $KeepFileNames) { [void]$keep.Add($name) }
    $removed = 0
    foreach ($file in Get-ChildItem -LiteralPath $fullDirectory -File -Force) {
        $obsoletePackage = $file.Extension -eq '.vsix' -and -not $keep.Contains($file.Name)
        $interruptedDownload = $file.Name -match '\.vsix\.[a-f0-9]{32}\.partial$'
        if (-not $obsoletePackage -and -not $interruptedDownload) { continue }
        if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($file.FullName)) -ne $fullDirectory -or
            ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "拒绝清理 VSIX 目录直属普通文件以外的目标：$($file.FullName)"
        }
        Remove-Item -LiteralPath $file.FullName -Force
        $removed++
        Write-Host "清理未引用的包或下载临时文件：$($file.Name)"
    }
    return $removed
}
