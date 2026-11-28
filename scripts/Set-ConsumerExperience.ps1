<#
.SYNOPSIS
    Turns off Windows consumer experiences (suggested apps, Spotlight, tips, widgets news feed), or reverts that.

.DESCRIPTION
    Writes the documented policy values under HKLM\SOFTWARE\Policies (machine-wide) and the per-user
    ContentDeliveryManager / CloudContent values under HKCU (the user running the script).

    -Revert removes the values this script sets, so Windows falls back to its own defaults. A policy set to
    0 is still a policy; removing it is what actually restores the default.

    HKCU settings apply to the account running the script. For every user, deploy this as a user-context
    script (Intune, logon script) or use the equivalent Intune settings catalog / Group Policy entries.

.PARAMETER Revert
    Remove the values instead of setting them.

.EXAMPLE
    .\Set-ConsumerExperience.ps1 -WhatIf

.EXAMPLE
    .\Set-ConsumerExperience.ps1 -Revert
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Revert)

$ErrorActionPreference = 'Stop'

# Hive, key path, value name, and the value that turns the consumer feature off.
$settings = @(
    [pscustomobject]@{ Hive = 'HKLM'; Key = 'SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableConsumerFeatures'; Off = 1 }
    [pscustomobject]@{ Hive = 'HKLM'; Key = 'SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableSoftLanding'; Off = 1 }
    [pscustomobject]@{ Hive = 'HKLM'; Key = 'SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsSpotlightFeatures'; Off = 1 }
    [pscustomobject]@{ Hive = 'HKLM'; Key = 'SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsSpotlightOnActionCenter'; Off = 1 }
    [pscustomobject]@{ Hive = 'HKLM'; Key = 'SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsSpotlightOnSettings'; Off = 1 }
    [pscustomobject]@{ Hive = 'HKLM'; Key = 'SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsSpotlightWindowsWelcomeExperience'; Off = 1 }
    [pscustomobject]@{ Hive = 'HKLM'; Key = 'SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableCdp'; Off = 0 }
    [pscustomobject]@{ Hive = 'HKLM'; Key = 'SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Off = 0 }
    [pscustomobject]@{ Hive = 'HKCU'; Key = 'SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsSpotlight'; Off = 1 }
    [pscustomobject]@{ Hive = 'HKCU'; Key = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Off = 0 }
    [pscustomobject]@{ Hive = 'HKCU'; Key = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353694Enabled'; Off = 0 }
    [pscustomobject]@{ Hive = 'HKCU'; Key = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Off = 0 }
    [pscustomobject]@{ Hive = 'HKCU'; Key = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Off = 0 }
)

$changed = 0
foreach ($s in $settings) {
    $key = '{0}:\{1}' -f $s.Hive, $s.Key
    $name = $s.Name
    if ($Revert) {
        if ((Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue) -and
            $PSCmdlet.ShouldProcess("$key\$name", 'Remove value')) {
            Remove-ItemProperty -Path $key -Name $name
            $changed++
        }
    }
    elseif ($PSCmdlet.ShouldProcess("$key\$name", "Set to $($s.Off)")) {
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name $name -Value $s.Off -PropertyType DWord -Force | Out-Null
        $changed++
    }
}

$state = if ($Revert) { 'restored to Windows defaults' } else { 'disabled' }
Write-Host "Consumer experiences $state ($changed value(s) changed)."
