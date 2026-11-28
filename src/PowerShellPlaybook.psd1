@{
    RootModule        = 'PowerShellPlaybook.psm1'
    ModuleVersion     = '0.4.0'
    GUID              = 'ddac9f09-a122-4d87-b3ed-8cd8f1b47025'

    Author            = 'Tim Heverin'
    CompanyName       = 'PowerShell Playbook'
    Copyright         = '(c) 2025-2026 Tim Heverin. MIT License.'
    Description       = 'PowerShell Playbook: identity, security, and endpoint reporting for AD, Entra ID, Intune, Exchange Online, and Windows. Falls back to mock data when no tenant or domain is reachable.'

    PowerShellVersion = '5.1'

    # Keep in sync with src/Public/*.ps1 (enforced by tests/ModuleLoad.Tests.ps1).
    FunctionsToExport = @(
        'Export-SupportBundle'
        'Get-CertificateExpiry'
        'Get-ConditionalAccessReport'
        'Get-DefenderStatus'
        'Get-ExchangeHygieneReport'
        'Get-InactiveAdAccounts'
        'Get-LocalAdminAudit'
        'Get-ServerRoleFeatureInventory'
        'Get-ToolkitUsageReport'
        'Invoke-IntuneBaseline'
        'Invoke-UserOffboarding'
        'Invoke-WinGetBaseline'
        'New-WinServerVmFromTemplate'
        'Send-PasswordExpiryNotifications'
        'Undo-UserOffboarding'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('Collect-SupportBundle')

    PrivateData       = @{
        PSData = @{
            Tags       = @('Automation', 'ActiveDirectory', 'EntraID', 'Intune', 'ExchangeOnline', 'Helpdesk', 'Reporting')
            LicenseUri = 'https://github.com/dj-3dub/PowerShell-Playbook/blob/main/LICENSE'
            ProjectUri = 'https://github.com/dj-3dub/PowerShell-Playbook'
        }
    }
}
