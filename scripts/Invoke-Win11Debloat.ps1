<#
.SYNOPSIS
    Runs the Windows 11 clean-up in one step: preinstalled app removal, consumer experience policies,
    and enterprise defaults. Audits by default.

.DESCRIPTION
    -Mode Audit (default)   Runs every step with -WhatIf and writes the app report, so you see exactly what
                            Remove would change. Works without elevation (scoped to the current user).
    -Mode Remove            Applies the changes. -AllUsers and provisioned-app removal need an elevated session.

    Steps (skip any with the -Skip* switches):
      1. Remove-PreinstalledApps.ps1   apps matched by config/debloat-appx.json
      2. Set-ConsumerExperience.ps1    suggested apps, Spotlight, tips, widgets news
      3. Set-EnterpriseDefaults.ps1    Remote Assistance, Xbox services, telemetry level

    For managed devices, prefer Intune/Group Policy for steps 2 and 3. This script suits standalone builds,
    labs and machines outside management.

.PARAMETER Mode
    Audit (default) or Remove.

.PARAMETER PolicyPath
    Keep/Remove policy for step 1. Default: <repo>/config/debloat-appx.json.

.PARAMETER AllUsers
    Step 1 removes apps for all users (elevation required).

.PARAMETER SkipProvisioned
    Step 1 leaves provisioned (image) packages alone.

.PARAMETER SkipApps
    Skip step 1.

.PARAMETER SkipConsumerExperience
    Skip step 2.

.PARAMETER SkipEnterpriseDefaults
    Skip step 3.

.EXAMPLE
    .\Invoke-Win11Debloat.ps1
    Audit everything and write the report.

.EXAMPLE
    .\Invoke-Win11Debloat.ps1 -Mode Remove -AllUsers -SkipEnterpriseDefaults
#>
[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Remove')][string]$Mode = 'Audit',
    [string]$PolicyPath = (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'config') 'debloat-appx.json'),
    [switch]$AllUsers,
    [switch]$SkipProvisioned,
    [switch]$SkipApps,
    [switch]$SkipConsumerExperience,
    [switch]$SkipEnterpriseDefaults
)

$ErrorActionPreference = 'Stop'

$isAdmin = $false
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch { Write-Verbose "Elevation check unavailable: $($_.Exception.Message)" }

$audit = ($Mode -eq 'Audit')
Write-Host '=== Windows 11 clean-up ===' -ForegroundColor Cyan
Write-Host "Mode: $Mode | AllUsers: $AllUsers | Provisioned: $(-not $SkipProvisioned) | Elevated: $isAdmin" -ForegroundColor Gray

if (-not $isAdmin) {
    if ($audit) {
        # An unelevated audit can only see the current user's apps.
        if ($AllUsers -or -not $SkipProvisioned) { Write-Host 'Not elevated: auditing current-user apps only.' -ForegroundColor Yellow }
        $AllUsers = $false
        $SkipProvisioned = $true
    }
    else {
        throw 'Remove mode changes machine-wide settings; run it from an elevated session.'
    }
}

if (-not $SkipApps) {
    & (Join-Path $PSScriptRoot 'Remove-PreinstalledApps.ps1') -PolicyPath $PolicyPath -AllUsers:$AllUsers `
        -SkipProvisioned:$SkipProvisioned -WhatIf:$audit | Out-Null
}
if (-not $SkipConsumerExperience) {
    & (Join-Path $PSScriptRoot 'Set-ConsumerExperience.ps1') -WhatIf:$audit
}
if (-not $SkipEnterpriseDefaults) {
    & (Join-Path $PSScriptRoot 'Set-EnterpriseDefaults.ps1') -WhatIf:$audit
}

Write-Host 'Done. See ./reports for the app removal report.' -ForegroundColor Green
