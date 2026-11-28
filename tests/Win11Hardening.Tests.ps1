# Windows 11 hardening/clean-up scripts. Registry, service and Appx cmdlets are mocked (and stubbed where
# the platform lacks them), so nothing on the test machine is changed.

BeforeDiscovery {
    $scriptsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
    $hardening = 'Set-EnterpriseDefaults', 'Set-ConsumerExperience', 'Remove-PreinstalledApps', 'Invoke-Win11Debloat' |
        ForEach-Object { @{ Name = $_; Path = Join-Path $scriptsDir "$_.ps1" } }
}

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $scriptsDir = Join-Path $root 'scripts'
    $script:createdStubs = @()
    $stubs = @{
        'Get-Service'                   = '[CmdletBinding()] param([Parameter(Position = 0)]$Name)'
        'Set-Service'                   = '[CmdletBinding()] param($Name, $StartupType)'
        'Stop-Service'                  = '[CmdletBinding()] param($Name, [switch]$Force)'
        'Get-AppxPackage'               = '[CmdletBinding()] param([switch]$AllUsers)'
        'Get-AppxProvisionedPackage'    = '[CmdletBinding()] param([switch]$Online)'
        'Remove-AppxPackage'            = '[CmdletBinding()] param($Package, [switch]$AllUsers)'
        'Remove-AppxProvisionedPackage' = '[CmdletBinding()] param([switch]$Online, $PackageName)'
    }
    foreach ($name in $stubs.Keys) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
            Set-Item "function:global:$name" -Value ([scriptblock]::Create($stubs[$name]))
            $script:createdStubs += $name
        }
    }
}

AfterAll {
    foreach ($name in $script:createdStubs) { Remove-Item "function:global:$name" -ErrorAction SilentlyContinue }
}

Describe '<Name>.ps1 help' -ForEach $hardening {
    It 'has a synopsis, a description and an example' {
        $help = Get-Help $Path -Full
        $help.Synopsis | Should -Not -Match '\.ps1'
        ($help.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }
}

Describe 'Switch parameters' {
    It 'no script under scripts/ or remediations/ has a [switch] that defaults to $true' {
        $offenders = foreach ($f in Get-ChildItem (Join-Path $root 'scripts'), (Join-Path $root 'remediations') -Recurse -Filter *.ps1) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.ParameterAst] -and
                    $n.StaticType -eq [switch] -and $n.DefaultValue -and $n.DefaultValue.Extent.Text -eq '$true'
                }, $true) | ForEach-Object { "$($f.Name): $($_.Name)" }
        }
        $offenders | Should -BeNullOrEmpty -Because 'a switch that defaults to on can only be turned off with -Name:$false'
    }
}

Describe 'Set-EnterpriseDefaults.ps1' {
    BeforeAll { $script = Join-Path $scriptsDir 'Set-EnterpriseDefaults.ps1' }
    BeforeEach {
        Mock Set-ItemProperty { }
        Mock New-ItemProperty { }
        Mock Remove-ItemProperty { }
        Mock New-Item { }
        Mock Test-Path { $true }
        Mock Get-ItemProperty { [pscustomobject]@{ AllowTelemetry = 1 } }
        Mock Get-Service { [pscustomobject]@{ Name = $Name } }
        Mock Set-Service { }
        Mock Stop-Service { }
        Mock Write-Host { }
    }

    It 'applies all three settings by default' {
        & $script
        Should -Invoke Set-ItemProperty -ParameterFilter { $Name -eq 'fAllowToGetHelp' -and $Value -eq 0 } -Times 1 -Exactly
        Should -Invoke Set-Service -ParameterFilter { $StartupType -eq 'Disabled' } -Times 4 -Exactly
        Should -Invoke New-ItemProperty -ParameterFilter { $Name -eq 'AllowTelemetry' -and $Value -eq 1 } -Times 1 -Exactly
    }

    It 'applies only the selected settings' {
        & $script -Setting Telemetry
        Should -Invoke Set-ItemProperty -Times 0 -Exactly
        Should -Invoke Set-Service -Times 0 -Exactly
        Should -Invoke New-ItemProperty -Times 1 -Exactly
    }

    It '-Revert restores defaults (policy value removed, services back to Manual)' {
        & $script -Revert
        Should -Invoke Remove-ItemProperty -ParameterFilter { $Name -eq 'AllowTelemetry' } -Times 1 -Exactly
        Should -Invoke Set-Service -ParameterFilter { $StartupType -eq 'Manual' } -Times 4 -Exactly
        Should -Invoke Set-ItemProperty -ParameterFilter { $Name -eq 'fAllowToGetHelp' -and $Value -eq 1 } -Times 1 -Exactly
    }

    It '-WhatIf changes nothing' {
        & $script -WhatIf
        foreach ($c in 'Set-ItemProperty', 'New-ItemProperty', 'Set-Service', 'Stop-Service') { Should -Invoke $c -Times 0 -Exactly }
    }
}

Describe 'Set-ConsumerExperience.ps1' {
    BeforeAll { $script = Join-Path $scriptsDir 'Set-ConsumerExperience.ps1' }
    BeforeEach {
        Mock New-ItemProperty { }
        Mock Remove-ItemProperty { }
        Mock New-Item { }
        Mock Test-Path { $true }
        Mock Write-Host { }
    }

    It 'sets every policy value' {
        & $script
        Should -Invoke New-ItemProperty -Times 13 -Exactly
        Should -Invoke New-ItemProperty -ParameterFilter { $Name -eq 'DisableConsumerFeatures' -and $Value -eq 1 -and $Path -like 'HKLM:*' } -Times 1 -Exactly
    }

    It '-Revert removes the values that exist instead of writing 0/1' {
        Mock Get-ItemProperty { if ($Name -like 'Disable*') { [pscustomobject]@{ $Name = 1 } } }
        & $script -Revert
        Should -Invoke New-ItemProperty -Times 0 -Exactly
        Should -Invoke Remove-ItemProperty -Times 7 -Exactly    # only the Disable* values exist in this mock
    }
}

Describe 'Remove-PreinstalledApps.ps1' {
    BeforeAll {
        $script = Join-Path $scriptsDir 'Remove-PreinstalledApps.ps1'
        $policy = Join-Path $TestDrive 'policy.json'
        @{ Keep = @('Contoso.Keep*'); Remove = @('Contoso.*') } | ConvertTo-Json | Set-Content $policy
    }
    BeforeEach {
        Mock Get-AppxPackage {
            [pscustomobject]@{ Name = 'Contoso.Bloat'; PackageFullName = 'Contoso.Bloat_1.0_x64'; Version = '1.0' }
            [pscustomobject]@{ Name = 'Contoso.KeepMe'; PackageFullName = 'Contoso.KeepMe_1.0_x64'; Version = '1.0' }
            [pscustomobject]@{ Name = 'Fabrikam.App'; PackageFullName = 'Fabrikam.App_1.0_x64'; Version = '1.0' }
        }
        Mock Get-AppxProvisionedPackage { [pscustomobject]@{ DisplayName = 'Contoso.Bloat'; PackageName = 'Contoso.Bloat_1.0_neutral'; Version = '1.0' } }
        Mock Remove-AppxPackage { }
        Mock Remove-AppxProvisionedPackage { }
        Mock Write-Host { }
    }

    It 'removes only remove-listed packages; the keep-list wins over the remove-list' {
        $rows = & $script -PolicyPath $policy -ReportPath (Join-Path $TestDrive 'r1') -Confirm:$false
        $rows.Package | Should -Not -Contain 'Contoso.KeepMe'
        $rows.Package | Should -Not -Contain 'Fabrikam.App'
        Should -Invoke Remove-AppxPackage -ParameterFilter { $Package -eq 'Contoso.Bloat_1.0_x64' } -Times 1 -Exactly
        Should -Invoke Remove-AppxProvisionedPackage -Times 1 -Exactly
        ($rows | Where-Object Status -ne 'Removed') | Should -BeNullOrEmpty
    }

    It '-WhatIf removes nothing but still writes the audit report' {
        $out = Join-Path $TestDrive 'r2'
        $rows = & $script -PolicyPath $policy -ReportPath $out -WhatIf
        Should -Invoke Remove-AppxPackage -Times 0 -Exactly
        $rows.Status | Sort-Object -Unique | Should -Be 'Planned'
        Get-ChildItem $out -Filter 'Debloat-Appx-*.html' | Should -Not -BeNullOrEmpty
    }

    It 'records a failed removal and carries on' {
        Mock Remove-AppxPackage { throw 'Package in use' }
        $rows = & $script -PolicyPath $policy -ReportPath (Join-Path $TestDrive 'r3') -Confirm:$false
        ($rows | Where-Object Scope -ne 'Provisioned').Status | Should -Be 'Failed'
        ($rows | Where-Object Scope -eq 'Provisioned').Status | Should -Be 'Removed'
    }

    It '-SkipProvisioned leaves the image alone' {
        $null = & $script -PolicyPath $policy -ReportPath (Join-Path $TestDrive 'r4') -SkipProvisioned -Confirm:$false
        Should -Invoke Get-AppxProvisionedPackage -Times 0 -Exactly
        Should -Invoke Remove-AppxProvisionedPackage -Times 0 -Exactly
    }
}
