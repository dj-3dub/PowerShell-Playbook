<#
.SYNOPSIS
    Applies (or reverts) a small set of enterprise endpoint defaults on Windows 10/11.

.DESCRIPTION
    Settings (all applied by default; choose a subset with -Setting):

      RemoteAssistance  Disable unsolicited Remote Assistance (fAllowToGetHelp = 0). Support uses
                        managed remote tools instead.
      XboxServices      Disable and stop the Xbox Live services (XblAuthManager, XblGameSave,
                        XboxGipSvc, XboxNetApiSvc).
      Telemetry         Set the diagnostic data policy to Required (AllowTelemetry = 1).

    -Revert undoes the selected settings: Remote Assistance is allowed again, the Xbox services go back to
    Manual, and the telemetry policy value is removed so Windows uses its default.

    Requires an elevated session. Supports -WhatIf / -Confirm. In a managed fleet these belong in Intune or
    Group Policy; this script is for standalone builds, labs, and machines outside that management.

.PARAMETER Setting
    Which settings to apply or revert. Default: all three.

.PARAMETER Revert
    Undo the selected settings instead of applying them.

.EXAMPLE
    .\Set-EnterpriseDefaults.ps1 -WhatIf

.EXAMPLE
    .\Set-EnterpriseDefaults.ps1 -Setting Telemetry, RemoteAssistance

.EXAMPLE
    .\Set-EnterpriseDefaults.ps1 -Revert
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('RemoteAssistance', 'XboxServices', 'Telemetry')]
    [string[]]$Setting = @('RemoteAssistance', 'XboxServices', 'Telemetry'),

    [switch]$Revert
)

$ErrorActionPreference = 'Stop'

$raKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'
$telKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
$xbox   = 'XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc'

if ('RemoteAssistance' -in $Setting) {
    $value = if ($Revert) { 1 } else { 0 }
    if ($PSCmdlet.ShouldProcess("$raKey\fAllowToGetHelp", "Set to $value")) {
        Set-ItemProperty -Path $raKey -Name fAllowToGetHelp -Value $value
    }
}

if ('XboxServices' -in $Setting) {
    foreach ($name in $xbox) {
        if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) { continue }
        if ($Revert) {
            if ($PSCmdlet.ShouldProcess("Service $name", 'Set startup type Manual')) {
                Set-Service -Name $name -StartupType Manual
            }
        }
        elseif ($PSCmdlet.ShouldProcess("Service $name", 'Stop and set startup type Disabled')) {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $name -StartupType Disabled
        }
    }
}

if ('Telemetry' -in $Setting) {
    if ($Revert) {
        if ((Get-ItemProperty -Path $telKey -Name AllowTelemetry -ErrorAction SilentlyContinue) -and
            $PSCmdlet.ShouldProcess("$telKey\AllowTelemetry", 'Remove policy value')) {
            Remove-ItemProperty -Path $telKey -Name AllowTelemetry
        }
    }
    elseif ($PSCmdlet.ShouldProcess("$telKey\AllowTelemetry", 'Set to 1 (Required)')) {
        if (-not (Test-Path $telKey)) { New-Item -Path $telKey -Force | Out-Null }
        New-ItemProperty -Path $telKey -Name AllowTelemetry -Value 1 -PropertyType DWord -Force | Out-Null
    }
}

$verb = if ($Revert) { 'Reverted' } else { 'Applied' }
Write-Host "$verb enterprise defaults: $($Setting -join ', ')."
