<#
.SYNOPSIS
    Intune remediation: re-enable the Windows Update services and trigger a scan.

.DESCRIPTION
    Runs as SYSTEM. Deliberately conservative, because this runs unattended across the fleet:
      - sets wuauserv and BITS back to Manual (their default) if they were Disabled, and starts them
      - asks the Windows Update Agent to detect now
    Installation and reboots stay under your Windows Update for Business / Intune update rings.
    The heavier component reset (renaming SoftwareDistribution/catroot2) is left to the helpdesk script
    scripts/helpdesk/Repair-WindowsUpdate.ps1, where a technician is present.
#>
[CmdletBinding()]
param()

try {
    $fixed = @()
    foreach ($name in 'BITS', 'wuauserv') {
        $svc = Get-Service -Name $name -ErrorAction Stop
        if ($svc.StartType -eq 'Disabled') {
            Set-Service -Name $name -StartupType Manual -ErrorAction Stop
            $fixed += $name
        }
        if ((Get-Service -Name $name).Status -ne 'Running') { Start-Service -Name $name -ErrorAction Stop }
    }

    (New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()

    $msg = 'Update scan triggered'
    if ($fixed) { $msg = "Re-enabled $($fixed -join ', '); $msg" }
    Write-Output $msg
    exit 0
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
