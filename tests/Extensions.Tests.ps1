# Tests for the PowerShell-Playbook.Extensions module. Vendor cmdlets (Az, Veeam, ...) are
# replaced by global stubs + Pester mocks, so the live code paths run without any cloud access.

BeforeAll {
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PowerShell-Playbook.Extensions.psd1'
    $moduleName = 'PowerShell-Playbook.Extensions'
    # Reports land in ./out under the current directory, so work inside TestDrive.
    Push-Location $TestDrive
    Import-Module $modulePath -Force -ErrorAction Stop

    $stubs = 'Get-AzContext', 'Get-AzVM', 'Get-AzDisk', 'Get-AzPublicIpAddress', 'Get-VBRJob', 'Get-VBRBackupSession'
    function New-GlobalStub([string]$Name) { Set-Item -Path "function:global:$Name" -Value { } }
}

AfterAll {
    Pop-Location
    foreach ($s in $stubs) { Remove-Item "function:global:$s" -ErrorAction SilentlyContinue }
    Remove-Module $moduleName -ErrorAction SilentlyContinue
}

Describe 'New-PlaybookReport' {
    It 'writes HTML with colour-coded Status cells and a status summary' {
        $out  = Join-Path $TestDrive 'report.html'
        $rows = @(
            [pscustomobject]@{ Item = 'a'; Status = 'OK' }
            [pscustomobject]@{ Item = 'b'; Status = 'Fail' }
        )
        New-PlaybookReport -Title 'Smoke' -Data $rows -Meta @{ Scope = 'test' } -OutFile $out | Should -Be $out
        $html = Get-Content $out -Raw
        $html | Should -Match '<td class="status ok">OK</td>'
        $html | Should -Match '<td class="status fail">Fail</td>'
        $html | Should -Match "chip fail'>Fail: 1"
    }

    It 'HTML-encodes the title and metadata' {
        $out = Join-Path $TestDrive 'encoded.html'
        New-PlaybookReport -Title '<script>x</script>' -Data ([pscustomobject]@{ A = 1 }) -Meta @{ K = '<b>' } -OutFile $out | Out-Null
        $html = Get-Content $out -Raw
        $html | Should -Not -Match '<script>x</script>'
        $html | Should -Match '&lt;script&gt;'
        $html | Should -Match '&lt;b&gt;'
    }
}

Describe 'Report functions without a connection' {
    # Nothing is installed on CI, so every function must report NotConnected instead of inventing data.
    It '<Name> returns only NotConnected rows' -ForEach @(
        @{ Name = 'Invoke-WindowsUpdateBaseline'; Run = { Invoke-WindowsUpdateBaseline -Provider Intune } }
        @{ Name = 'Test-BackupRestoreReadiness';  Run = { Test-BackupRestoreReadiness -JobName 'Daily' } }
        @{ Name = 'Get-VMwareHealth';             Run = { Get-VMwareHealth -Server 'vc01' } }
        @{ Name = 'Get-CloudBaseline';            Run = { Get-CloudBaseline -Provider Both } }
        @{ Name = 'Get-O365TenantHealth';         Run = { Get-O365TenantHealth -IncludeSharingChecks } }
    ) {
        $result = & $Run
        $result.Html | Should -Exist
        $result.Csv  | Should -Exist
        $result.Rows | ForEach-Object { $_.Status | Should -Be 'NotConnected' }
    }
}

Describe 'Mock mode' {
    It '<Name> -Mock tags every row as sample data' -ForEach @(
        @{ Name = 'Invoke-WindowsUpdateBaseline'; Run = { Invoke-WindowsUpdateBaseline -Mock } }
        @{ Name = 'Test-BackupRestoreReadiness';  Run = { Test-BackupRestoreReadiness -JobName A, B -Mock } }
        @{ Name = 'Get-VMwareHealth';             Run = { Get-VMwareHealth -Server 'vc01' -Mock } }
        @{ Name = 'Get-CloudBaseline';            Run = { Get-CloudBaseline -Provider Both -Mock } }
        @{ Name = 'Get-O365TenantHealth';         Run = { Get-O365TenantHealth -IncludeForwardingRules -Mock } }
    ) {
        $result = & $Run
        $result.Rows.Count | Should -BeGreaterThan 0
        $result.Rows | ForEach-Object { $_.Source | Should -Be 'Mock' }
        Get-Content $result.Html -Raw | Should -Match '\(sample data\)'
    }
}

Describe 'Get-CloudBaseline (Azure, mocked)' {
    BeforeAll {
        foreach ($s in 'Get-AzContext', 'Get-AzVM', 'Get-AzDisk', 'Get-AzPublicIpAddress') { New-GlobalStub $s }
    }

    BeforeEach {
        Mock -ModuleName $moduleName Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-test' } } }
        Mock -ModuleName $moduleName Get-AzVM { 1..3 | ForEach-Object { [pscustomobject]@{ Name = "vm$_" } } }
        Mock -ModuleName $moduleName Get-AzDisk {
            [pscustomobject]@{ Name = 'disk-attached'; DiskState = 'Attached' }
            [pscustomobject]@{ Name = 'disk-orphan';   DiskState = 'Unattached' }
        }
        Mock -ModuleName $moduleName Get-AzPublicIpAddress {
            [pscustomobject]@{ Name = 'pip-in-use'; IpConfiguration = 'nic1'; NatGateway = $null }
        }
    }

    It 'counts VMs, flags unattached disks, and passes when all public IPs are in use' {
        $rows = (Get-CloudBaseline -Provider Azure).Rows
        $byCheck = @{}; $rows | ForEach-Object { $byCheck[$_.Check] = $_ }

        $byCheck['Virtual machines'].Count          | Should -Be 3
        $byCheck['Unattached managed disks'].Count  | Should -Be 1
        $byCheck['Unattached managed disks'].Status | Should -Be 'Warn'
        $byCheck['Unattached managed disks'].Detail | Should -Be 'disk-orphan'
        $byCheck['Unassociated public IPs'].Status  | Should -Be 'OK'
        $rows | ForEach-Object { $_.Source | Should -Be 'Live'; $_.Scope | Should -Be 'sub-test' }
    }

    It 'reports NotConnected when there is no Az context' {
        Mock -ModuleName $moduleName Get-AzContext { $null }
        $rows = (Get-CloudBaseline -Provider Azure).Rows
        $rows.Status | Should -Be 'NotConnected'
        Should -Invoke -ModuleName $moduleName Get-AzVM -Times 0 -Exactly
    }
}

Describe 'Test-BackupRestoreReadiness (Veeam, mocked)' {
    BeforeAll {
        foreach ($s in 'Get-VBRJob', 'Get-VBRBackupSession') { New-GlobalStub $s }
    }

    BeforeEach {
        Mock -ModuleName $moduleName Get-VBRBackupSession {
            $now = Get-Date
            [pscustomobject]@{ JobName = 'Fresh';  Result = 'Success'; EndTime = $now.AddHours(-3) }
            [pscustomobject]@{ JobName = 'Fresh';  Result = 'Failed';  EndTime = $now.AddDays(-3) }   # older failure is ignored
            [pscustomobject]@{ JobName = 'Stale';  Result = 'Success'; EndTime = $now.AddHours(-50) }
            [pscustomobject]@{ JobName = 'Broken'; Result = 'Failed';  EndTime = $now.AddHours(-2) }
        }
    }

    It 'grades the latest session per job against the RPO' {
        $result = Test-BackupRestoreReadiness -JobName Fresh, Stale, Broken, Missing -MaxAgeHours 26
        $status = @{}; $result.Rows | ForEach-Object { $status[$_.Job] = $_.Status }

        $status['Fresh']   | Should -Be 'OK'
        $status['Stale']   | Should -Be 'Warn'
        $status['Broken']  | Should -Be 'Fail'
        $status['Missing'] | Should -Be 'Fail'
        $result.Evidence   | Should -Exist
    }
}
