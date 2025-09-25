@{
    # Script module file associated with this manifest.
    RootModule = 'PowerShell-Playbook.Extensions.psm1'

    # Version number of this module.
    ModuleVersion = '0.1.0'

    # ID used to uniquely identify this module
    GUID = '3f9b6e2a-7c4d-4f2b-9e1b-2c9a4d5f6e7a'

    # Author of this module
    Author = 'Tim Heverin'

    # Company or vendor of this module
    CompanyName = 'EnterpriseOpsToolkit'

    # Copyright statement for this module
    Copyright = '(c) Tim Heverin. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Extensions for PowerShell Playbook: extra reporters and cloud/hypervisor helpers.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Optional provider modules (listed under PSData.ExternalModuleDependencies)

    # Functions to export. Keep explicit list to avoid exporting everything unexpectedly.
    FunctionsToExport = @(
        'New-PlaybookReport',
        'Invoke-WindowsUpdateBaseline',
        'Test-BackupRestoreReadiness',
        'Get-VMwareHealth',
        'Get-CloudBaseline',
        'Get-O365TenantHealth',
        'Publish-ReportToTicket'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{ 
        PSData = @{ 
            Tags = 'PowerShell','Playbook','Extensions','Enterprise'
            ProjectUri = 'https://github.com/dj-3dub/PowerShell-Playbook'
            ExternalModuleDependencies = @(
                'Az.Accounts',
                'Microsoft.Graph.Authentication',
                'ExchangeOnlineManagement',
                'AWSPowerShell.NetCore',
                'VCF.PowerCLI'
            )
        }
    }
}
