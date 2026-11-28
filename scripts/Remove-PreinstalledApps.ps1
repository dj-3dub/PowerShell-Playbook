<#
.SYNOPSIS
    Removes preinstalled Windows apps that match a remove-list, never touching anything on the keep-list.

.DESCRIPTION
    Reads a policy file (default: config/debloat-appx.json) with two lists of wildcard patterns:
      Keep    always kept, even if it also matches Remove (Store, App Installer, runtimes, Company Portal, ...)
      Remove  removed for the current user (or all users with -AllUsers), and from the provisioned image so
              new profiles don't get them (skip with -SkipProvisioned)

    Writes an HTML + CSV report of every matching package and its outcome (Planned under -WhatIf, Removed or
    Failed), even when run with -WhatIf, so the report doubles as an audit.

    -AllUsers and provisioned removal require an elevated session.

.PARAMETER PolicyPath
    Keep/Remove policy JSON. Default: <repo>/config/debloat-appx.json.

.PARAMETER AllUsers
    Remove for all user profiles instead of only the current user.

.PARAMETER SkipProvisioned
    Leave provisioned (image) packages alone.

.PARAMETER ReportPath
    Folder for the report. Default ./reports.

.EXAMPLE
    .\Remove-PreinstalledApps.ps1 -WhatIf
    Audit: report what would be removed.

.EXAMPLE
    .\Remove-PreinstalledApps.ps1 -AllUsers
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$PolicyPath = (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'config') 'debloat-appx.json'),
    [switch]$AllUsers,
    [switch]$SkipProvisioned,
    [string]$ReportPath = './reports'
)

$ErrorActionPreference = 'Stop'
# Report and CSV helpers shared with the modules.
Get-ChildItem -Path (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'Shared') -Filter *.ps1 | ForEach-Object { . $_.FullName }

if (-not (Test-Path $PolicyPath)) { throw "Policy file not found: $PolicyPath" }
$policy = Get-Content $PolicyPath -Raw | ConvertFrom-Json
$keep = @($policy.Keep)
$remove = @($policy.Remove)

function Test-AnyMatch([string]$Value, [string[]]$Patterns) {
    foreach ($p in $Patterns) { if ($Value -like $p) { return $true } }
    $false
}
function Test-ShouldRemove([string]$Name) {
    (-not (Test-AnyMatch $Name $keep)) -and (Test-AnyMatch $Name $remove)
}

Write-Host 'Scanning Appx packages...' -ForegroundColor Cyan
$installed = @(Get-AppxPackage -AllUsers:$AllUsers | Where-Object { Test-ShouldRemove $_.Name } | Sort-Object Name)
$provisioned = @()
if (-not $SkipProvisioned) {
    $provisioned = @(Get-AppxProvisionedPackage -Online | Where-Object { Test-ShouldRemove $_.DisplayName } | Sort-Object DisplayName)
}
Write-Host ("Matched {0} installed and {1} provisioned package(s)." -f $installed.Count, $provisioned.Count) -ForegroundColor Yellow

$rows = New-Object System.Collections.Generic.List[object]
foreach ($a in $installed) {
    $row = [pscustomobject]@{ Scope = $(if ($AllUsers) { 'All users' } else { 'Current user' }); Package = $a.Name; Version = [string]$a.Version; Status = 'Planned'; Detail = $a.PackageFullName }
    if ($PSCmdlet.ShouldProcess($a.Name, "Remove-AppxPackage (AllUsers: $AllUsers)")) {
        try { Remove-AppxPackage -Package $a.PackageFullName -AllUsers:$AllUsers; $row.Status = 'Removed' }
        catch { $row.Status = 'Failed'; $row.Detail = $_.Exception.Message }
    }
    $rows.Add($row)
}
foreach ($p in $provisioned) {
    $row = [pscustomobject]@{ Scope = 'Provisioned'; Package = $p.DisplayName; Version = [string]$p.Version; Status = 'Planned'; Detail = $p.PackageName }
    if ($PSCmdlet.ShouldProcess($p.DisplayName, 'Remove-AppxProvisionedPackage -Online')) {
        try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName | Out-Null; $row.Status = 'Removed' }
        catch { $row.Status = 'Failed'; $row.Detail = $_.Exception.Message }
    }
    $rows.Add($row)
}

# The report is an audit record: write it even under -WhatIf.
New-Item -ItemType Directory -Force -Path $ReportPath -WhatIf:$false -Confirm:$false | Out-Null
$base = Join-Path $ReportPath ('Debloat-Appx-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmm'))
$rows | Export-PlaybookCsv -Path "$base.csv"
$mode = if ($WhatIfPreference) { 'Audit (WhatIf)' } else { 'Remove' }
ConvertTo-ReportHtml -Title 'Preinstalled App Removal' -Data $rows.ToArray() `
    -Meta ([ordered]@{ Mode = $mode; Policy = (Split-Path $PolicyPath -Leaf); Computer = $env:COMPUTERNAME }) |
    Out-File -FilePath "$base.html" -Encoding UTF8 -WhatIf:$false -Confirm:$false
Write-Host "Report: $base.html" -ForegroundColor Green

$rows
