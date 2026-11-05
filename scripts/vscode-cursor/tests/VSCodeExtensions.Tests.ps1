#Requires -Version 7.0
BeforeAll {
    $script:exportScript = Join-Path $PSScriptRoot '../Export-VSCodeExtensions.ps1'
    $script:installScript = Join-Path $PSScriptRoot '../Install-VSCodeExtensions.ps1'
    $script:commonScript = Join-Path $PSScriptRoot '../VSCodeExtensions.Common.ps1'
    . $script:commonScript

    function New-TestVsix {
        param([string]$Path, [string]$Id = 'sample.tool', [string]$Version = '1.2.3', [string]$Platform = 'universal')
        $publisher, $name = $Id -split '\.', 2
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry = $archive.CreateEntry('extension/package.json')
            $writer = [IO.StreamWriter]::new($entry.Open())
            try { $writer.Write((@{publisher=$publisher; name=$name; version=$Version} | ConvertTo-Json)) }
            finally { $writer.Dispose() }
            $entry = $archive.CreateEntry('extension.vsixmanifest')
            $writer = [IO.StreamWriter]::new($entry.Open())
            $platformAttribute = if ($Platform -eq 'universal') { '' } else { " TargetPlatform=`"$Platform`"" }
            try { $writer.Write("<PackageManifest xmlns=`"http://schemas.microsoft.com/developer/vsx-schema/2011`"><Metadata><Identity Publisher=`"$publisher`" Id=`"$name`" Version=`"$Version`"$platformAttribute /></Metadata></PackageManifest>") }
            finally { $writer.Dispose() }
        }
        finally { $archive.Dispose() }
    }

    function New-TestBundle {
        param([string]$Root, [string[]]$Ids = @('sample.tool'))
        $vsix = Join-Path $Root 'vsix'
        New-Item -ItemType Directory -Path $vsix -Force | Out-Null
        $entries = @(foreach ($id in $Ids) {
            $file = "$id-1.2.3-universal.vsix"
            $path = Join-Path $vsix $file
            New-TestVsix -Path $path -Id $id
            @{id=$id; version='1.2.3'; targetPlatform='universal'; file=$file; sha256=(Get-FileHash -LiteralPath $path).Hash; status='ready'}
        })
        @{schemaVersion=1; complete=$true; extensions=$entries} | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $Root 'manifest.json')
    }

    function Write-TestSource {
        param([string]$Path, [string[]]$Ids = @('sample.tool'), [string]$Platform = 'undefined')
        $records = @(foreach ($id in $Ids) { @{identifier=@{id=$id}; version='1.2.3'; metadata=@{targetPlatform=$Platform}} })
        ConvertTo-Json -InputObject $records -Depth 10 | Set-Content -LiteralPath $Path
    }

    function Read-TestState { Get-Content -LiteralPath $env:VSCODE_SYNC_TEST_STATE -Raw | ConvertFrom-Json -AsHashtable }
    function Save-TestState($State) { $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $env:VSCODE_SYNC_TEST_STATE }
}

Describe 'VS Code offline export' {
    BeforeEach {
        $script:caseDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:caseDir | Out-Null
        $script:sourceJson = Join-Path $script:caseDir 'extensions.json'
        $script:outputDir = Join-Path $script:caseDir 'bundle'
        Write-TestSource -Path $script:sourceJson
        Mock Invoke-WebRequest {
            $parts = ([uri]$Uri).AbsolutePath.Split('/')
            $platform = if (([uri]$Uri).Query) { ([uri]$Uri).Query -replace '^\?targetPlatform=', '' } else { 'universal' }
            New-TestVsix -Path $OutFile -Id "$($parts[5]).$($parts[7])" -Version $parts[8] -Platform $platform
        }
    }

    It 'Exports one installed version and copies a runnable installer into the bundle' {
        & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0
        $manifest = Get-Content (Join-Path $script:outputDir 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.complete | Should -BeTrue
        @($manifest.extensions).Count | Should -Be 1
        $manifest.extensions[0].version | Should -Be '1.2.3'
        $manifest.extensions[0].targetPlatform | Should -Be 'universal'
        $manifest.extensions[0].sha256 | Should -Match '^[a-f0-9]{64}$'
        Test-Path (Join-Path $script:outputDir 'Install-VSCodeExtensions.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:outputDir 'VSCodeExtensions.Common.ps1') | Should -BeTrue
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/sample/vsextensions/tool/1.2.3/vspackage' }
    }

    It 'Requests and verifies the exact installed target platform' {
        Write-TestSource -Path $script:sourceJson -Platform 'win32-x64'
        & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0
        $manifest = Get-Content (Join-Path $script:outputDir 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.extensions[0].targetPlatform | Should -Be 'win32-x64'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*?targetPlatform=win32-x64' }
    }

    It 'Reuses packages only after checking their previous hash' {
        & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0
        & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }

    It 'Redownloads a modified cached package instead of blessing its new hash' {
        & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0
        Set-Content (Join-Path $script:outputDir 'vsix/sample.tool-1.2.3-universal.vsix') 'truncated'
        & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly
    }

    It 'Records missing packages, continues with the rest, and leaves no partial downloads' {
        Write-TestSource -Path $script:sourceJson -Ids @('sample.missing', 'sample.tool')
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile 'partial'; throw 'network failure' } -ParameterFilter { $Uri -like '*/missing/*' }
        { & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 1 -RetryDelaySeconds 0 } | Should -Throw '*导出未完成*'
        $manifest = Get-Content (Join-Path $script:outputDir 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.complete | Should -BeFalse
        @($manifest.extensions | Where-Object status -eq failed).Count | Should -Be 1
        @($manifest.extensions | Where-Object status -eq ready).Count | Should -Be 1
        @(Get-ChildItem $script:outputDir -Recurse -Filter '*.partial').Count | Should -Be 0
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Uri -like '*/missing/*' }
    }

    It 'Rejects a Marketplace response containing the wrong version' {
        Mock Invoke-WebRequest { New-TestVsix -Path $OutFile -Version '9.9.9' }
        { & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0 } | Should -Throw '*导出未完成*'
        Test-Path (Join-Path $script:outputDir 'vsix/sample.tool-1.2.3-universal.vsix') | Should -BeFalse
    }

    It 'Rejects workspace recommendations rather than exporting an empty bundle' {
        '{"recommendations":["sample.tool"]}' | Set-Content $script:sourceJson
        { & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir } | Should -Throw '*已安装扩展数组*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'Rejects conflicting installed versions before downloading' {
        '[{"identifier":{"id":"sample.tool"},"version":"1.2.3"},{"identifier":{"id":"sample.tool"},"version":"2.0.0"}]' | Set-Content $script:sourceJson
        { & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir } | Should -Throw '*不同版本或平台*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'Prunes old versions, removed extensions and interrupted downloads only after a successful export' {
        & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0
        $vsixDir = Join-Path $script:outputDir 'vsix'
        $oldFile = Join-Path $vsixDir 'sample.tool-1.0.0-universal.vsix'
        $removedFile = Join-Path $vsixDir 'sample.removed-1.0.0-universal.vsix'
        $partialFile = Join-Path $vsixDir ('sample.old-1.0.0-universal.vsix.' + [guid]::NewGuid().ToString('N') + '.partial')
        Set-Content -LiteralPath $oldFile 'old package'
        Set-Content -LiteralPath $removedFile 'removed package'
        Set-Content -LiteralPath $partialFile 'interrupted download'
        Set-Content -LiteralPath (Join-Path $vsixDir 'notes.txt') 'keep notes'
        & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0
        Test-Path -LiteralPath $oldFile | Should -BeFalse
        Test-Path -LiteralPath $removedFile | Should -BeFalse
        Test-Path -LiteralPath $partialFile | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $vsixDir 'notes.txt') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $vsixDir -Filter '*.vsix').Count | Should -Be 1
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }

    It 'Keeps old packages if a new export fails' {
        & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0
        $oldFile = Join-Path $script:outputDir 'vsix/sample.tool-1.2.3-universal.vsix'
        Write-TestSource -Path $script:sourceJson -Ids @('sample.missing')
        Mock Invoke-WebRequest { throw 'network failure' }
        { & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0 } | Should -Throw '*导出未完成*'
        Test-Path -LiteralPath $oldFile | Should -BeTrue
        (Get-Content (Join-Path $script:outputDir 'manifest.json') -Raw | ConvertFrom-Json).complete | Should -BeFalse
    }

    It 'Can mirror an explicitly empty installed-extension array' {
        & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0
        '[]' | Set-Content -LiteralPath $script:sourceJson
        & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0
        $manifest = Get-Content (Join-Path $script:outputDir 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.complete | Should -BeTrue
        @($manifest.extensions).Count | Should -Be 0
        @(Get-ChildItem (Join-Path $script:outputDir 'vsix') -Filter '*.vsix').Count | Should -Be 0
    }

    It 'Does not mark the export complete when stale-package cleanup fails' {
        Mock Remove-Item { throw 'simulated locked file' } -ParameterFilter { $LiteralPath -like '*obsolete.vsix' }
        New-Item -ItemType Directory -Path (Join-Path $script:outputDir 'vsix') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:outputDir 'vsix/obsolete.vsix') 'old package'
        { & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0 } | Should -Throw '*清理未引用的 VSIX 失败*'
        (Get-Content (Join-Path $script:outputDir 'manifest.json') -Raw | ConvertFrom-Json).complete | Should -BeFalse
    }

    It 'Refuses a redirected VSIX directory before changing the bundle' {
        $outside = Join-Path $script:caseDir 'outside'
        New-Item -ItemType Directory -Path $outside, $script:outputDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'obsolete.vsix') 'outside package'
        $junction = Join-Path $script:outputDir 'vsix'
        New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
        try {
            { & $script:exportScript -JsonPath $script:sourceJson -OutputDir $script:outputDir -RetryCount 0 } | Should -Throw '*目录联接*'
            Test-Path -LiteralPath (Join-Path $outside 'obsolete.vsix') | Should -BeTrue
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }
        finally { Remove-Item -LiteralPath $junction -Force }
    }
}

Describe 'VS Code offline installation with an isolated fake CLI' {
    BeforeEach {
        $script:previousStatePath = $env:VSCODE_SYNC_TEST_STATE
        $script:caseDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:caseDir | Out-Null
        $env:VSCODE_SYNC_TEST_STATE = Join-Path $script:caseDir 'state.json'
        $script:bundle = Join-Path $script:caseDir 'bundle with spaces'
        New-TestBundle -Root $script:bundle
        Save-TestState @{installed=@{}; calls=@(); failIds=@(); uninstallFailIds=@(); uninstallBlockedBy=@{}; uninstallCascade=@{}; ignoreInstall=$false; ignoreUninstall=$false; listExitCode=0}
        $script:fakeCode = Join-Path $script:caseDir 'fake-code.ps1'
        @'
$ErrorActionPreference = 'Stop'
$state = Get-Content -LiteralPath $env:VSCODE_SYNC_TEST_STATE -Raw | ConvertFrom-Json -AsHashtable
$state.calls += ,@($args)
if ($args -contains '--list-extensions') {
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $env:VSCODE_SYNC_TEST_STATE
    foreach ($id in $state.installed.Keys) { "$id@$($state.installed[$id])" }
    exit $state.listExitCode
}
if ($args -contains '--uninstall-extension') {
    $id = $args[1]
    $blocked = $false
    if ($state.uninstallBlockedBy.Contains($id)) {
        foreach ($dependent in $state.uninstallBlockedBy[$id]) {
            if ($state.installed.Contains($dependent)) { $blocked = $true }
        }
    }
    if ($state.uninstallFailIds -contains $id -or $blocked -or -not $state.installed.Contains($id)) {
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $env:VSCODE_SYNC_TEST_STATE
        'simulated uninstall failure'
        exit 8
    }
    if (-not $state.ignoreUninstall) {
        [void]$state.installed.Remove($id)
        if ($state.uninstallCascade.Contains($id)) {
            foreach ($member in $state.uninstallCascade[$id]) { [void]$state.installed.Remove($member) }
        }
    }
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $env:VSCODE_SYNC_TEST_STATE
    exit 0
}
if ($args -notcontains '--install-extension' -or $args -notcontains '--do-not-include-pack-dependencies') { throw 'Unexpected CLI arguments' }
$archive = [IO.Compression.ZipFile]::OpenRead($args[1])
try {
    $reader = [IO.StreamReader]::new($archive.GetEntry('extension/package.json').Open())
    try { $package = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
} finally { $archive.Dispose() }
$id = "$($package.publisher).$($package.name)"
if ($state.failIds -contains $id) {
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $env:VSCODE_SYNC_TEST_STATE
    'simulated CLI failure'
    exit 7
}
if (-not $state.ignoreInstall) { $state.installed[$id] = $package.version }
$state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $env:VSCODE_SYNC_TEST_STATE
exit 0
'@ | Set-Content -LiteralPath $script:fakeCode
    }

    AfterEach { $env:VSCODE_SYNC_TEST_STATE = $script:previousStatePath }

    It 'Installs a single VSIX using its whole path and verifies the final version' {
        & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode -ProfileName 'Offline Work'
        $state = Read-TestState
        $state.installed['sample.tool'] | Should -Be '1.2.3'
        $state.calls.Count | Should -Be 3
        $state.calls[1][1] | Should -Be (Join-Path $script:bundle 'vsix/sample.tool-1.2.3-universal.vsix')
        $state.calls[1] | Should -Contain '--force'
        foreach ($call in $state.calls) { $call | Should -Contain 'Offline Work' }
    }

    It 'Skips matching versions and uninstalls extra extensions in the selected profile' {
        $state = Read-TestState
        $state.installed = @{'sample.tool'='1.2.3'; 'internal.extra'='5.0.0'}
        Save-TestState $state
        & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode -ProfileName 'Offline Work'
        $state = Read-TestState
        $state.installed.Contains('internal.extra') | Should -BeFalse
        @($state.calls | Where-Object { $_ -contains '--install-extension' }).Count | Should -Be 0
        @($state.calls | Where-Object { $_ -contains '--uninstall-extension' }).Count | Should -Be 1
        foreach ($call in $state.calls) { $call | Should -Contain 'Offline Work' }
    }

    It 'Runs the copied installer from a transferred bundle without the repository' {
        $sourceJson = Join-Path $script:caseDir 'extensions.json'
        Write-TestSource -Path $sourceJson
        Mock Invoke-WebRequest { New-TestVsix -Path $OutFile }
        $exportedBundle = Join-Path $script:caseDir 'exported'
        & $script:exportScript -JsonPath $sourceJson -OutputDir $exportedBundle -RetryCount 0
        $transferredBundle = Join-Path $script:caseDir '内网 副本'
        Copy-Item -LiteralPath $exportedBundle -Destination $transferredBundle -Recurse
        & (Join-Path $transferredBundle 'Install-VSCodeExtensions.ps1') -CodeCmd $script:fakeCode
        (Read-TestState).installed['sample.tool'] | Should -Be '1.2.3'
    }

    It 'Replaces a different version including an existing newer one' {
        $state = Read-TestState
        $state.installed['sample.tool'] = '9.9.9'
        Save-TestState $state
        & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode
        (Read-TestState).installed['sample.tool'] | Should -Be '1.2.3'
    }

    It 'Rejects an incomplete export before invoking the CLI' {
        $path = Join-Path $script:bundle 'manifest.json'
        $manifest = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
        $manifest.complete = $false
        $manifest | ConvertTo-Json -Depth 10 | Set-Content $path
        { & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode } | Should -Throw '*导出未完成*'
        (Read-TestState).calls.Count | Should -Be 0
    }

    It 'Rejects a missing package before invoking the CLI' {
        Remove-Item -LiteralPath (Join-Path $script:bundle 'vsix/sample.tool-1.2.3-universal.vsix')
        { & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode } | Should -Throw '*离线包缺失*'
        (Read-TestState).calls.Count | Should -Be 0
    }

    It 'Checks all packages before installing anything' {
        $secondBundle = Join-Path $script:caseDir 'two packages'
        New-TestBundle -Root $secondBundle -Ids @('sample.first', 'sample.second')
        Add-Content -LiteralPath (Join-Path $secondBundle 'vsix/sample.second-1.2.3-universal.vsix') 'tampered'
        { & $script:installScript -BundleDir $secondBundle -CodeCmd $script:fakeCode } | Should -Throw '*SHA-256*'
        (Read-TestState).calls.Count | Should -Be 0
    }

    It 'Continues after CLI failure but throws a failure summary' {
        $secondBundle = Join-Path $script:caseDir 'two packages'
        New-TestBundle -Root $secondBundle -Ids @('sample.first', 'sample.second')
        $state = Read-TestState
        $state.failIds = @('sample.first')
        $state.installed['internal.extra'] = '5.0.0'
        Save-TestState $state
        { & $script:installScript -BundleDir $secondBundle -CodeCmd $script:fakeCode } | Should -Throw '*sample.first*'
        (Read-TestState).installed['sample.second'] | Should -Be '1.2.3'
        (Read-TestState).installed['internal.extra'] | Should -Be '5.0.0'
        @((Read-TestState).calls | Where-Object { $_ -contains '--uninstall-extension' }).Count | Should -Be 0
    }

    It 'Reports a false successful CLI installation as a version mismatch' {
        $state = Read-TestState
        $state.ignoreInstall = $true
        $state.installed['internal.extra'] = '5.0.0'
        Save-TestState $state
        { & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode } | Should -Throw '*同步失败*'
        (Read-TestState).installed['internal.extra'] | Should -Be '5.0.0'
        @((Read-TestState).calls | Where-Object { $_ -contains '--uninstall-extension' }).Count | Should -Be 0
    }

    It 'Aborts when the initial installed-extension query fails' {
        $state = Read-TestState
        $state.listExitCode = 9
        Save-TestState $state
        { & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode } | Should -Throw '*退出码 9*'
        @((Read-TestState).calls | Where-Object { $_ -contains '--install-extension' }).Count | Should -Be 0
    }

    It 'Reports failed uninstall commands and keeps failed removals visible' {
        $state = Read-TestState
        $state.installed = @{'sample.tool'='1.2.3'; 'internal.extra'='5.0.0'}
        $state.uninstallFailIds = @('internal.extra')
        Save-TestState $state
        { & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode } | Should -Throw '*镜像同步失败*'
        (Read-TestState).installed['internal.extra'] | Should -Be '5.0.0'
    }

    It 'Verifies that successful uninstall commands actually removed the extra extension' {
        $state = Read-TestState
        $state.installed = @{'sample.tool'='1.2.3'; 'internal.extra'='5.0.0'}
        $state.ignoreUninstall = $true
        Save-TestState $state
        { & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode } | Should -Throw '*镜像同步失败*'
    }

    It 'Uninstalls all user extensions for an explicitly empty complete snapshot' {
        $emptyBundle = Join-Path $script:caseDir 'empty bundle'
        New-TestBundle -Root $emptyBundle -Ids @()
        $state = Read-TestState
        $state.installed = @{'sample.one'='1.0.0'; 'sample.two'='2.0.0'}
        Save-TestState $state
        & $script:installScript -BundleDir $emptyBundle -CodeCmd $script:fakeCode
        (Read-TestState).installed.Count | Should -Be 0
        @((Read-TestState).calls | Where-Object { $_ -contains '--uninstall-extension' }).Count | Should -Be 2
    }

    It 'Rejects a null extension list instead of treating it as an empty mirror' {
        '{"schemaVersion":1,"complete":true,"extensions":null}' | Set-Content -LiteralPath (Join-Path $script:bundle 'manifest.json')
        { & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode } | Should -Throw '*扩展数组*'
        (Read-TestState).calls.Count | Should -Be 0
    }

    It 'Cleans stale packages left by an ordinary copy into the inner-network bundle' {
        $stalePackage = Join-Path $script:bundle 'vsix/sample.tool-0.1.0-universal.vsix'
        Set-Content -LiteralPath $stalePackage 'obsolete copied package'
        & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode
        Test-Path -LiteralPath $stalePackage | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:bundle 'vsix/sample.tool-1.2.3-universal.vsix') | Should -BeTrue
    }

    It 'Restores retained targets when uninstalling an extra pack removes its members' {
        $state = Read-TestState
        $state.installed = @{'sample.tool'='1.2.3'; 'internal.pack'='1.0.0'}
        $state.uninstallCascade['internal.pack'] = @('sample.tool')
        Save-TestState $state
        & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode
        (Read-TestState).installed['sample.tool'] | Should -Be '1.2.3'
        (Read-TestState).installed.Count | Should -Be 1
        @((Read-TestState).calls | Where-Object { $_ -contains '--install-extension' }).Count | Should -Be 1
    }

    It 'Treats an already cascaded extra member as removed rather than a failure' {
        $state = Read-TestState
        $state.installed = @{'sample.tool'='1.2.3'; 'aaa.pack'='1.0.0'; 'zzz.member'='1.0.0'}
        $state.uninstallCascade['aaa.pack'] = @('zzz.member')
        Save-TestState $state
        & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode
        (Read-TestState).installed.Count | Should -Be 1
    }

    It 'Retries blocked extra dependencies after their dependents have been removed' {
        $state = Read-TestState
        $state.installed = @{'sample.tool'='1.2.3'; 'internal.a-base'='1.0.0'; 'internal.z-dependent'='1.0.0'}
        $state.uninstallBlockedBy['internal.a-base'] = @('internal.z-dependent')
        Save-TestState $state
        & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode
        (Read-TestState).installed.Count | Should -Be 1
        @((Read-TestState).calls | Where-Object { $_ -contains '--uninstall-extension' }).Count | Should -Be 3
    }

    It 'Reports a bundle cleanup failure even when installed extensions already match' {
        Set-Content -LiteralPath (Join-Path $script:bundle 'vsix/obsolete.vsix') 'old package'
        Mock Remove-Item { throw 'simulated locked file' } -ParameterFilter { $LiteralPath -like '*obsolete.vsix' }
        { & $script:installScript -BundleDir $script:bundle -CodeCmd $script:fakeCode } | Should -Throw '*用户扩展已对齐*'
        (Read-TestState).installed['sample.tool'] | Should -Be '1.2.3'
    }
}
