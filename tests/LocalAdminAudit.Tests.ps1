# Cross-platform-safe tests for Get-LocalAdminAudit.

BeforeAll {
    $manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PowerShellPlaybook.psd1'
    Import-Module $manifest -Force -ErrorAction Stop -WarningAction SilentlyContinue
}

AfterAll {
    Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
}

Describe 'Local Admin Audit' {
    It 'exports Get-LocalAdminAudit' {
        Get-Command Get-LocalAdminAudit -Module PowerShellPlaybook | Should -Not -BeNullOrEmpty
    }

    # Uses LocalAccounts/ADSI, so only meaningful on Windows.
    It 'returns data and writes HTML + CSV reports' -Skip:(-not $IsWindows) {
        $out    = Join-Path $TestDrive 'reports'
        $result = Get-LocalAdminAudit -ComputerName localhost -OutputPath $out

        $result | Should -Not -BeNullOrEmpty
        Get-ChildItem -Path $out -Filter 'LocalAdmins-*.html' | Should -Not -BeNullOrEmpty
        Get-ChildItem -Path $out -Filter 'LocalAdmins-*.csv'  | Should -Not -BeNullOrEmpty
    }
}
