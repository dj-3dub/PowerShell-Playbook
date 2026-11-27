# Identity governance reports (fall back to mock data when no AD is reachable).

BeforeAll {
    $manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PowerShellPlaybook.psd1'
    Import-Module $manifest -Force -ErrorAction Stop -WarningAction SilentlyContinue
}

AfterAll {
    Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
}

Describe 'Identity Governance' {
    It 'produces an inactive accounts report' {
        $path = Get-InactiveAdAccounts -DaysInactive 60 -OutputPath (Join-Path $TestDrive 'reports')
        $path | Should -Not -BeNullOrEmpty
        $path | Should -Exist
    }

    It 'builds password expiry notifications in Preview mode' {
        $path = Send-PasswordExpiryNotifications -Days 14 -Preview -OutputPath (Join-Path $TestDrive 'out')
        $path | Should -Not -BeNullOrEmpty
        $path | Should -Exist
    }
}
