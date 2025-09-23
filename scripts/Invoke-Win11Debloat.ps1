[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Audit','Remove')][string]$Mode = 'Audit',
    [string]$PolicyPath = ".\config\debloat-appx.json",
    [switch]$AllUsers,
    [switch]$RemoveProvisioned = $true,
    [switch]$NoConsumerTweaks,
    [switch]$NoEnterpriseDefaults
)

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

$IsAdmin = Test-IsAdmin

Write-Host "=== Enterprise Debloat Orchestrator ===" -ForegroundColor Cyan
Write-Host "Mode: $Mode  | AllUsers: $AllUsers  | RemoveProvisioned: $RemoveProvisioned  | Admin: $IsAdmin" -ForegroundColor Gray

# ---- Preflight: make Audit mode painless; keep Remove mode safe ----
if ($Mode -eq 'Audit') {
    if (-not $IsAdmin) {
        # Auto-scope to current user & skip provisioned when not elevated
        if ($AllUsers.IsPresent) {
            Write-Host "Preflight: Not elevated → forcing -AllUsers:$false for Audit." -ForegroundColor Yellow
        }
        if ($RemoveProvisioned.IsPresent) {
            Write-Host "Preflight: Not elevated → forcing -RemoveProvisioned:$false for Audit." -ForegroundColor Yellow
        }
        $AllUsers = $false
        $RemoveProvisioned = $false
    }
} else {
    # Remove mode: require elevation for cross-user and provisioned actions
    if (($AllUsers -or $RemoveProvisioned) -and -not $IsAdmin) {
        Write-Warning "Remove mode with -AllUsers or -RemoveProvisioned requires **Run as Administrator**. Aborting."
        return
    }
}

# Shared args
$debloatArgs = @{
    PolicyPath        = $PolicyPath
    AllUsers          = $AllUsers
    ReportPath        = ".\reports"
    RemoveProvisioned = $RemoveProvisioned
}

# Run remover (Audit writes report for real; removals still WhatIf)
if ($Mode -eq 'Audit') {
    & "$PSScriptRoot\Remove-PreinstalledApps.ps1" @debloatArgs -WhatIf -WriteReport
} else {
    & "$PSScriptRoot\Remove-PreinstalledApps.ps1" @debloatArgs
}

# In Audit mode, forward -WhatIf to tweaks so no changes occur
$whatIf = ($Mode -eq 'Audit')

if (-not $NoConsumerTweaks) {
    & "$PSScriptRoot\Set-ConsumerExperience.ps1" -Disable -WhatIf:$whatIf
}

if (-not $NoEnterpriseDefaults) {
    & "$PSScriptRoot\Set-EnterpriseDefaults.ps1" -WhatIf:$whatIf
}

Write-Host "Done. See reports folder for HTML summary (if any)." -ForegroundColor Green
