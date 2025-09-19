[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DisableRemoteAssistance = $true,
    [switch]$DisableXboxServices = $true,
    [switch]$DisableTelemetryBasic = $true
)

if ($DisableRemoteAssistance) {
    if ($PSCmdlet.ShouldProcess("System", "Disable Remote Assistance")) {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Name fAllowToGetHelp -Value 0 -Force
    }
}
if ($DisableXboxServices) {
    $svc = @('XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc')
    foreach ($s in $svc) {
        if ($PSCmdlet.ShouldProcess("Service:$s", "Set StartupType Disabled and Stop")) {
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
        }
    }
}
if ($DisableTelemetryBasic) {
    if ($PSCmdlet.ShouldProcess('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','Set AllowTelemetry=1')) {
        New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 1 -PropertyType DWord -Force | Out-Null
    }
}
Write-Host "Baseline enterprise defaults applied."
