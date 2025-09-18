
@{
    RootModule        = 'EnterpriseOpsToolkit.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '3a1c2c4f-9b7d-4e3e-9c1d-aaa0a0a0a0a0'
    Author            = 'Tim Heverin'
    CompanyName       = 'EnterpriseOpsToolkit'
    Copyright         = '(c) Tim Heverin. All rights reserved.'
    PowerShellVersion = '5.1'
    Description       = 'Enterprise automation toolkit for Entra/Intune/EXO/Windows with PS7-first design.'
    FunctionsToExport = @(
        'Get-EotConditionalAccessReport',
        'Get-EotExchangeHygiene',
        'Invoke-EotIntuneBaseline'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('PowerShell','Automation','Intune','Graph','Exchange','Enterprise')
            ProjectUri = 'https://github.com/dj-3dub/EnterpriseOpsToolkit'
        }
    }
}
