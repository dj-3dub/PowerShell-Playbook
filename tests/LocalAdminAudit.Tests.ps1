# tests/LocalAdminAudit.Tests.ps1
# Cross-platform-safe tests for Get-LocalAdminAudit

$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'src/PowerShellPlaybook.psd1'

Describe 'Local Admin Audit' {
    BeforeAll {
        if (-not (Test-Path $manifest)) {
            throw "Module manifest not found at: $manifest"
        }
        Import-Module $manifest -Force
    }

    It 'exports Get-LocalAdminAudit' {
        Get-Command Get-LocalAdminAudit -ErrorAction SilentlyContinue |
        Should -Not -BeNullOrEmpty
    }

    # Windows-only execution test (uses LocalAccounts/ADSI)
    It 'produces data and writes a report on Windows' -Skip:(!$IsWindows) {
        $out = Join-Path $TestDrive 'reports'
        $result = Get-LocalAdminAudit -ComputerName localhost -OutputPath $out -Verbose

        # Should return objects
        $result | Should -Not -BeNullOrEmpty

        # Should have written an HTML report
        (Get-ChildItem -Path $out -Filter 'LocalAdmins-*.html' -ErrorAction SilentlyContinue) |
        Should -Not -BeNullOrEmpty

        # And a CSV too
        (Get-ChildItem -Path $out -Filter 'LocalAdmins-*.csv' -ErrorAction SilentlyContinue) |
        Should -Not -BeNullOrEmpty
    }
}
