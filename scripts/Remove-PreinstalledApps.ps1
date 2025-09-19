[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
param(
    [string]$PolicyPath = ".\config\debloat-appx.json",
    [switch]$AllUsers,
    [string]$ReportPath = ".\reports",
    [switch]$RemoveProvisioned = $true,

    # NEW: save the report even when running with -WhatIf (Audit mode)
    [switch]$WriteReport
)

# Load policy
if (-not (Test-Path $PolicyPath)) { throw "Policy file not found: $PolicyPath" }
$policy = Get-Content $PolicyPath -Raw | ConvertFrom-Json
$keep = @($policy.Keep)
$deny = @($policy.Remove)

function Test-AnyMatch($value, $patterns) {
    foreach ($p in $patterns) { if ($value -like $p) { return $true } }
    return $false
}

Write-Host "Scanning Appx packages..." -ForegroundColor Cyan

$appsCurrent = Get-AppxPackage -AllUsers:$AllUsers | Sort-Object Name
$prov = if ($RemoveProvisioned) { Get-AppxProvisionedPackage -Online } else { @() }

$toRemoveCurrent = @()
foreach ($a in $appsCurrent) {
    if (Test-AnyMatch $a.Name $keep) { continue }
    if (Test-AnyMatch $a.Name $deny) { $toRemoveCurrent += $a; continue }
}

$toRemoveProv = @()
foreach ($p in $prov) {
    if (Test-AnyMatch $p.DisplayName $keep) { continue }
    if (Test-AnyMatch $p.DisplayName $deny) { $toRemoveProv += $p; continue }
}

Write-Host ("Found {0} current-user app(s) and {1} provisioned app(s) to remove." -f $toRemoveCurrent.Count, $toRemoveProv.Count) -ForegroundColor Yellow

# --- HTML report (force write even under -WhatIf) ---
function New-ReportHtml($title, $data) {
@"
<!DOCTYPE html>
<html><head><meta charset='utf-8'><title>$title</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:24px}
table{border-collapse:collapse;width:100%}
th,td{border:1px solid #ddd;padding:6px;text-align:left}
th{background:#f4f4f4}
h1{margin-top:0}
</style>
</head><body>
<h1>$title</h1>
$data
</body></html>
"@
}

$curRows = $toRemoveCurrent | Select-Object Name, PackageFullName, Publisher, Version | ConvertTo-Html -Fragment
$provRows = $toRemoveProv   | Select-Object DisplayName, PackageName, Version     | ConvertTo-Html -Fragment
$report   = New-ReportHtml -title "Debloat Appx Summary ($(Get-Date))" -data ($curRows + $provRows)
$reportFile = Join-Path $ReportPath ("Debloat-Appx-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmm'))

# Force actual write for the report even if -WhatIf was passed
New-Item -ItemType Directory -Force -Path $ReportPath -WhatIf:$false -Confirm:$false | Out-Null
$report | Out-File -FilePath $reportFile -Encoding UTF8 -WhatIf:$false -Confirm:$false
Write-Host "Report: $reportFile" -ForegroundColor Green

# --- Removals (honor -WhatIf) ---
foreach ($a in $toRemoveCurrent) {
    if ($PSCmdlet.ShouldProcess($a.Name, "Remove-AppxPackage -AllUsers:$AllUsers")) {
        try { Remove-AppxPackage -Package $a.PackageFullName -AllUsers:$AllUsers -ErrorAction Stop }
        catch { Write-Warning "Failed to remove current package $($a.Name): $($_.Exception.Message)" }
    }
}

foreach ($p in $toRemoveProv) {
    if ($PSCmdlet.ShouldProcess($p.DisplayName, "Remove-AppxProvisionedPackage -Online")) {
        try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null }
        catch { Write-Warning "Failed to remove provisioned package $($p.DisplayName): $($_.Exception.Message)" }
    }
}
