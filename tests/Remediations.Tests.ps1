# Intune remediation pairs (remediations/<Name>/Detect.ps1 + Remediate.ps1) and the Graph publisher.
# Windows-only dependencies (CIM, services, w32tm, Windows Update COM) are stubbed so this runs anywhere.

BeforeDiscovery {
    $remRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'remediations'
    $folders = Get-ChildItem $remRoot -Directory | ForEach-Object { @{ Name = $_.Name; Dir = $_.FullName } }
}

BeforeAll {
    $remRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'remediations'
    $script:createdStubs = @()
    # Shared mutable state for mock bodies ($script: inside a mock resolves to Pester's scope, not this file's).
    $state = @{}
    $stubs = @{
        'Get-CimInstance'       = '[CmdletBinding()] param($ClassName, $Filter)'
        'Get-Service'           = '[CmdletBinding()] param([Parameter(Position = 0)][string[]]$Name)'
        'Set-Service'           = '[CmdletBinding()] param($Name, $StartupType)'
        'Start-Service'         = '[CmdletBinding()] param($Name)'
        'w32tm'                 = 'param([Parameter(ValueFromRemainingArguments)]$Rest)'
        'Invoke-MgGraphRequest' = '[CmdletBinding()] param($Method, $Uri, $Body, $ContentType)'
        'Get-MgContext'         = '[CmdletBinding()] param()'
    }
    foreach ($name in $stubs.Keys) {
        # Only stub what this platform lacks (w32tm is always stubbed so the real exe never runs).
        if ($name -eq 'w32tm' -or -not (Get-Command $name -CommandType Cmdlet, Function -ErrorAction SilentlyContinue)) {
            Set-Item "function:global:$name" -Value ([scriptblock]::Create($stubs[$name]))
            $script:createdStubs += $name
        }
    }
    function Invoke-Remediation([string]$Name, [string]$Script, [hashtable]$Params = @{}) {
        $output = & (Join-Path (Join-Path $remRoot $Name) $Script) @Params
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join ' ') }
    }
    function New-Disk([double]$FreeGB, [double]$SizeGB = 256) {
        [pscustomobject]@{ FreeSpace = $FreeGB * 1GB; Size = $SizeGB * 1GB }
    }
}

AfterAll {
    foreach ($name in $script:createdStubs) { Remove-Item "function:global:$name" -ErrorAction SilentlyContinue }
}

Describe 'Remediation package <Name>' -ForEach $folders {
    It 'has Detect.ps1, Remediate.ps1 and valid remediation.json' {
        Join-Path $Dir 'Detect.ps1'    | Should -Exist
        Join-Path $Dir 'Remediate.ps1' | Should -Exist
        $meta = Get-Content (Join-Path $Dir 'remediation.json') -Raw | ConvertFrom-Json
        $meta.displayName  | Should -Match '^PowerShell Playbook - '
        $meta.description  | Should -Not -BeNullOrEmpty
        $meta.runAsAccount | Should -BeIn 'system', 'user'
    }

    It 'is self-contained (Intune uploads single files with no modules)' {
        foreach ($f in 'Detect.ps1', 'Remediate.ps1') {
            $text = Get-Content (Join-Path $Dir $f) -Raw
            $text | Should -Not -Match 'Import-Module|#Requires\s+-Modules|\$PSScriptRoot'
            $text | Should -Match 'exit 0'
            $text | Should -Match 'exit 1'
        }
    }
}

Describe 'LowDiskSpace' {
    It 'Detect exits 1 below the threshold and 0 above it' {
        Mock Get-CimInstance { New-Disk 5 }
        (Invoke-Remediation LowDiskSpace Detect.ps1).ExitCode | Should -Be 1
        Mock Get-CimInstance { New-Disk 80 }
        (Invoke-Remediation LowDiskSpace Detect.ps1).ExitCode | Should -Be 0
    }

    It 'Remediate deletes only files older than the cutoff and reports success once space is back' {
        $tmp = Join-Path $TestDrive 'temp'
        New-Item -ItemType Directory -Path (Join-Path $tmp 'sub') -Force | Out-Null
        $old = Join-Path $tmp 'sub/old.tmp'; $new = Join-Path $tmp 'new.tmp'
        Set-Content $old 'x'; Set-Content $new 'x'
        (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-30)

        $state.calls = 0
        Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
            $state.calls++; if ($state.calls -eq 1) { New-Disk 5 } else { New-Disk 40 }
        }
        $r = Invoke-Remediation LowDiskSpace Remediate.ps1 @{ CleanupPath = $tmp }

        $r.ExitCode | Should -Be 0
        $old | Should -Not -Exist
        Join-Path $tmp 'sub' | Should -Not -Exist
        $new | Should -Exist
    }

    It 'Remediate exits 1 when the drive is still low afterwards' {
        Mock Get-CimInstance { New-Disk 3 }
        $r = Invoke-Remediation LowDiskSpace Remediate.ps1 @{ CleanupPath = (Join-Path $TestDrive 'empty') }
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match '^Still low'
    }
}

Describe 'TeamsCacheSize' {
    BeforeEach {
        $saved = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive "local-$(New-Guid)"
        $cache = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        $fs = [IO.File]::Create((Join-Path $cache 'blob.dat')); $fs.SetLength(60MB); $fs.Dispose()
    }
    AfterEach { $env:LOCALAPPDATA = $saved }

    It 'Detect flags a cache over the limit' {
        (Invoke-Remediation TeamsCacheSize Detect.ps1 @{ MaxCacheMB = 50 }).ExitCode  | Should -Be 1
        (Invoke-Remediation TeamsCacheSize Detect.ps1 @{ MaxCacheMB = 100 }).ExitCode | Should -Be 0
    }

    It 'Remediate leaves the cache alone while Teams is running' {
        Mock Get-Process -ParameterFilter { $Name -eq 'ms-teams' } { [pscustomobject]@{ Name = 'ms-teams' } }
        (Invoke-Remediation TeamsCacheSize Remediate.ps1).ExitCode | Should -Be 1
        Join-Path $cache 'blob.dat' | Should -Exist
    }

    It 'Remediate clears the cache when Teams is closed' {
        Mock Get-Process -ParameterFilter { $Name -eq 'ms-teams' } { }
        (Invoke-Remediation TeamsCacheSize Remediate.ps1).ExitCode | Should -Be 0
        Get-ChildItem $cache -Force | Should -BeNullOrEmpty
    }
}

Describe 'TimeSync' {
    BeforeEach {
        $state.offset = '+00.0153462s'
        $state.source = 'DC01.corp.local'
        Mock Get-Service { [pscustomobject]@{ Name = 'W32Time'; Status = 'Running'; StartType = 'Automatic' } }
        Mock w32tm {
            $a = $Rest -join ' '
            if ($a -like '/query /source*') { $state.source }
            elseif ($a -like '/stripchart*') { 'Tracking DC01.corp.local [10.0.0.10:123].', "18:00:00, $($state.offset)" }
        }
    }

    It 'Detect passes when in sync, and flags skew, no source, or a stopped service' {
        (Invoke-Remediation TimeSync Detect.ps1).ExitCode | Should -Be 0

        $state.offset = '+125.0000000s'
        (Invoke-Remediation TimeSync Detect.ps1).Output | Should -Match 'Clock skew'

        $state.offset = '+00.01s'; $state.source = 'Local CMOS Clock'
        (Invoke-Remediation TimeSync Detect.ps1).ExitCode | Should -Be 1

        Mock Get-Service { [pscustomobject]@{ Name = 'W32Time'; Status = 'Stopped' } }
        (Invoke-Remediation TimeSync Detect.ps1).Output | Should -Match 'Stopped'
    }

    It 'Detect handles a comma decimal separator' {
        $state.offset = '+00,0153462s'
        (Invoke-Remediation TimeSync Detect.ps1).ExitCode | Should -Be 0
    }

    It 'Remediate uses the domain hierarchy on domain-joined machines and resyncs' {
        Mock Set-Service { }
        Mock Start-Service { }
        Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $true } }
        $r = Invoke-Remediation TimeSync Remediate.ps1
        $r.ExitCode | Should -Be 0
        Should -Invoke w32tm -ParameterFilter { ($Rest -join ' ') -like '/config /syncfromflags:domhier*' } -Times 1 -Exactly
        Should -Invoke w32tm -ParameterFilter { ($Rest -join ' ') -eq '/resync /force' } -Times 1 -Exactly
    }

    It 'Remediate configures NTP on a workgroup machine with no source' {
        Mock Set-Service { }
        Mock Start-Service { }
        Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $false } }
        $state.source = 'Local CMOS Clock'
        $null = Invoke-Remediation TimeSync Remediate.ps1
        Should -Invoke w32tm -ParameterFilter { ($Rest -join ' ') -like '/config /manualpeerlist:time.windows.com,0x9*' } -Times 1 -Exactly
    }
}

# New-Object -ComObject only exists on Windows, so these run on the Windows CI runner.
Describe 'StaleWindowsUpdate' -Skip:($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
    BeforeEach {
        $state.lastInstall = (Get-Date).AddDays(-10)
        $state.wuStart = 'Manual'
        Mock Get-Service {
            foreach ($n in $Name) { [pscustomobject]@{ Name = $n; Status = 'Running'; StartType = $(if ($n -eq 'wuauserv') { $state.wuStart } else { 'Manual' }) } }
        }
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } {
            $searcher = [pscustomobject]@{}
            $searcher | Add-Member ScriptMethod GetTotalHistoryCount { 2 }
            $searcher | Add-Member ScriptMethod QueryHistory {
                [pscustomobject]@{ Operation = 1; ResultCode = 2; Date = $state.lastInstall; Title = '2026-11 Cumulative Update' }
                [pscustomobject]@{ Operation = 1; ResultCode = 4; Date = (Get-Date); Title = 'Failed driver' }
            }
            $session = [pscustomobject]@{ Searcher = $searcher }
            $session | Add-Member ScriptMethod CreateUpdateSearcher { $this.Searcher }
            $session
        }
    }

    It 'Detect ignores failed installs and compares the last success to the limit' {
        (Invoke-Remediation StaleWindowsUpdate Detect.ps1).ExitCode | Should -Be 0
        $state.lastInstall = (Get-Date).AddDays(-60)
        (Invoke-Remediation StaleWindowsUpdate Detect.ps1).Output | Should -Match '60 day'
    }

    It 'Detect flags a disabled update service' {
        $state.wuStart = 'Disabled'
        (Invoke-Remediation StaleWindowsUpdate Detect.ps1).Output | Should -Match 'Disabled service\(s\): wuauserv'
    }

    It 'Remediate re-enables a disabled service and triggers a scan' {
        $state.wuStart = 'Disabled'
        $state.detected = $false
        Mock Set-Service { }
        Mock Start-Service { }
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.AutoUpdate' } {
            $o = [pscustomobject]@{}; $o | Add-Member ScriptMethod DetectNow { $state.detected = $true }; $o
        }
        $r = Invoke-Remediation StaleWindowsUpdate Remediate.ps1
        $r.ExitCode | Should -Be 0
        Should -Invoke Set-Service -ParameterFilter { $Name -eq 'wuauserv' -and $StartupType -eq 'Manual' } -Times 1 -Exactly
        $state.detected | Should -BeTrue
    }
}

Describe 'Publish-IntuneRemediation.ps1' {
    BeforeEach {
        Mock Get-MgContext { [pscustomobject]@{ Account = 'admin@corp.local' } }
        $state.sent = @()
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET') { return @{ value = @(@{ id = 'existing-id'; displayName = 'PowerShell Playbook - Time sync' }) } }
            $state.sent += [pscustomobject]@{ Method = $Method; Uri = $Uri; Body = ($Body | ConvertFrom-Json) }
            @{ id = 'new-id' }
        }
        $publish = Join-Path $remRoot 'Publish-IntuneRemediation.ps1'
    }

    It 'updates an existing remediation and creates a new one, with the scripts base64-encoded' {
        $r = & $publish -Path (Join-Path $remRoot 'TimeSync'), (Join-Path $remRoot 'TeamsCacheSize') -Confirm:$false

        ($r | Where-Object Name -like '*Time sync').Action | Should -Be 'Updated'
        ($r | Where-Object Name -like '*Teams*').Action    | Should -Be 'Created'
        ($state.sent | Where-Object Method -eq 'PATCH').Uri | Should -Match '/existing-id$'

        $teams = ($state.sent | Where-Object Method -eq 'POST').Body
        $teams.runAsAccount | Should -Be 'user'
        $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($teams.detectionScriptContent))
        $decoded | Should -Be (Get-Content (Join-Path $remRoot 'TeamsCacheSize/Detect.ps1') -Raw)
    }

    It '-WhatIf sends nothing' {
        $null = & $publish -WhatIf
        $state.sent | Should -BeNullOrEmpty
    }
}
