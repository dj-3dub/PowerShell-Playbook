
# Pester v5 tests
Import-Module "$PSScriptRoot/../src/EnterpriseOpsToolkit.psd1" -Force

Describe 'EnterpriseOpsToolkit basics' {
    It 'exports key functions' {
        Get-Command Get-EotConditionalAccessReport | Should -Not -BeNullOrEmpty
        Get-Command Get-EotExchangeHygiene | Should -Not -BeNullOrEmpty
        Get-Command Invoke-EotIntuneBaseline | Should -Not -BeNullOrEmpty
    }

    It 'generates CA report (mock)' {
        $out = Get-EotConditionalAccessReport -Environment Dev -OutputPath (Join-Path $PSScriptRoot '../out')
        Test-Path $out | Should -BeTrue
    }
}
