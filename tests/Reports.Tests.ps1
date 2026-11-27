# Validates that report generators produce HTML files (mock data where no tenant/domain exists).

BeforeAll {
    $manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PowerShellPlaybook.psd1'
    Import-Module $manifest -Force -ErrorAction Stop -WarningAction SilentlyContinue
    $reports = Join-Path $TestDrive 'reports'
}

AfterAll {
    Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
}

Describe 'Report generators' {
    It 'creates a Conditional Access HTML report (mock config)' {
        $null = Get-ConditionalAccessReport -Environment Dev -OutputPath $reports
        Get-ChildItem $reports -Filter 'ConditionalAccess-*.html' | Should -Not -BeNullOrEmpty
    }

    It 'creates a Local Admin HTML report' {
        $null = Get-LocalAdminReport -OutputPath $reports 6>$null
        Get-ChildItem $reports -Filter 'LocalAdmins-*.html' | Should -Not -BeNullOrEmpty
    }

    It 'creates a Certificate Expiry HTML report' {
        $null = Get-CertificateExpiry -ExpiresInDays 60 -OutputPath $reports 6>$null
        Get-ChildItem $reports -Filter 'CertExpiry-*.html' | Should -Not -BeNullOrEmpty
    }
}
