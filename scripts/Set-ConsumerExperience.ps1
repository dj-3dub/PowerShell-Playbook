[CmdletBinding(SupportsShouldProcess)]
param([switch]$Disable = $true)

function Set-RegDword {
    param(
        [Parameter(Mandatory)][ValidateSet('HKLM','HKCU')][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )
    $fullPath = "$Root`:\$Path"
    if (-not (Test-Path $fullPath)) {
        if ($PSCmdlet.ShouldProcess($fullPath, "New-Item")) {
            New-Item -Path $fullPath -Force | Out-Null
        }
    }
    if ($PSCmdlet.ShouldProcess("$fullPath\\$Name", "Set-ItemProperty = $Value")) {
        New-ItemProperty -Path $fullPath -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
    }
}

$actions = @()
if ($Disable) {
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableConsumerFeatures' -Value 1 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableSoftLanding' -Value 1 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\System' -Name 'EnableCdp' -Value 0 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightFeatures' -Value 1 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightOnActionCenter' -Value 1 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightOnSettings' -Value 1 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightWindowsWelcomeExperience' -Value 1 }
    $actions += { Set-RegDword -Root HKCU -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlight' -Value 1 }
    $actions += { Set-RegDword -Root HKCU -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-338388Enabled' -Value 0 }
    $actions += { Set-RegDword -Root HKCU -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-353694Enabled' -Value 0 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0 }
    $actions += { Set-RegDword -Root HKCU -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SoftLandingEnabled' -Value 0 }
    $actions += { Set-RegDword -Root HKCU -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SystemPaneSuggestionsEnabled' -Value 0 }
} else {
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableConsumerFeatures' -Value 0 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableSoftLanding' -Value 0 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\System' -Name 'EnableCdp' -Value 1 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightFeatures' -Value 0 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightOnActionCenter' -Value 0 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightOnSettings' -Value 0 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightWindowsWelcomeExperience' -Value 0 }
    $actions += { Set-RegDword -Root HKCU -Path 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlight' -Value 0 }
    $actions += { Set-RegDword -Root HKCU -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-338388Enabled' -Value 1 }
    $actions += { Set-RegDword -Root HKCU -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-353694Enabled' -Value 1 }
    $actions += { Set-RegDword -Root HKLM -Path 'SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 1 }
    $actions += { Set-RegDword -Root HKCU -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SoftLandingEnabled' -Value 1 }
    $actions += { Set-RegDword -Root HKCU -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SystemPaneSuggestionsEnabled' -Value 1 }
}
foreach ($a in $actions) { & $a }
Write-Host "Consumer experiences have been $([string]::Copy($(if ($Disable) {'disabled'} else {'enabled'})))."
