[CmdletBinding()]
param(
    [switch]$Fix
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path .
$src = Join-Path $root 'src'
$psd1 = Join-Path $src  'PowerShellPlaybook.psd1'
$psm1 = Join-Path $src  'PowerShellPlaybook.psm1'
$pub = Join-Path $src  'Public'
$pri = Join-Path $src  'Private'

Write-Host "=== PowerShell Playbook Diagnostics ===" -ForegroundColor Cyan
Write-Host "Root: $root" -ForegroundColor DarkCyan

# 1) Existence checks
$issues = @()

if (-not (Test-Path $psd1)) { $issues += "Missing manifest: $psd1" }
if (-not (Test-Path $psm1)) { $issues += "Missing module:   $psm1" }
if (-not (Test-Path $pub)) { $issues += "Missing folder:   $pub" }
if (-not (Test-Path $pri)) { $issues += "Missing folder:   $pri" }

# 2) Read manifest + validate RootModule
$rootModuleOk = $false
if (Test-Path $psd1) {
    $raw = Get-Content $psd1 -Raw
    $rm = [regex]::Match($raw, "RootModule\s*=\s*'([^']+)'")
    if ($rm.Success) {
        $rootModule = $rm.Groups[1].Value
        Write-Host "Manifest RootModule: $rootModule"
        if ($rootModule -ne 'PowerShellPlaybook.psm1') {
            $issues += "RootModule points to '$rootModule' (expected 'PowerShellPlaybook.psm1')"
            if ($Fix) {
                $raw = $raw -replace "RootModule\s*=\s*'[^']+'", "RootModule = 'PowerShellPlaybook.psm1'"
                Set-Content $psd1 -Value $raw -Encoding UTF8
                Write-Host "Fixed: RootModule -> PowerShellPlaybook.psm1" -ForegroundColor Green
                $rootModuleOk = $true
            }
        } else {
            $rootModuleOk = $true
        }
    } else {
        $issues += "Could not read RootModule from manifest."
    }
}

# 3) Validate psm1 autoloader for Public/Private
$psm1Text = if (Test-Path $psm1) { Get-Content $psm1 -Raw } else { "" }
$needPub = -not ($psm1Text -match "Get-ChildItem\s+.*Public.*-Filter\s+\*\.ps1")
$needPri = -not ($psm1Text -match "Get-ChildItem\s+.*Private.*-Filter\s+\*\.ps1")

if ($needPub -or $needPri) {
    $issues += "psm1 missing autoloaders for Public/Private scripts."
    if ($Fix -and (Test-Path $psm1)) {
        @"
# --- Auto-load Private helpers
Get-ChildItem -Path (Join-Path \$PSScriptRoot 'Private') -Filter *.ps1 -ErrorAction SilentlyContinue |
  ForEach-Object { . \$_.FullName }

# --- Auto-load Public functions
Get-ChildItem -Path (Join-Path \$PSScriptRoot 'Public') -Filter *.ps1 -ErrorAction SilentlyContinue |
  ForEach-Object { . \$_.FullName }
"@ | Add-Content -Path $psm1 -Encoding UTF8
        Write-Host "Fixed: added autoloader blocks to psm1" -ForegroundColor Green
        $psm1Text = Get-Content $psm1 -Raw
    }
}

# 4) Check that every Public/Private ps1 actually exists & is loadable
$pubFiles = if (Test-Path $pub) { Get-ChildItem $pub -Filter *.ps1 -File -ErrorAction SilentlyContinue } else { @() }
$priFiles = if (Test-Path $pri) { Get-ChildItem $pri -Filter *.ps1 -File -ErrorAction SilentlyContinue } else { @() }

Write-Host ("Public scripts  : {0}" -f $pubFiles.Count)
Write-Host ("Private scripts : {0}" -f $priFiles.Count)

# 5) Try import the module cleanly
Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
$importOk = $false
try {
    Import-Module $psd1 -Force -ErrorAction Stop
    $importOk = $true
    Write-Host "Module imported successfully." -ForegroundColor Green
} catch {
    $issues += "Import-Module failed: $($_.Exception.Message)"
}

# 6) List exported commands to confirm scope
if ($importOk) {
    $cmds = Get-Command -Module PowerShellPlaybook | Sort-Object Name
    Write-Host ("Exported commands: {0}" -f $cmds.Count) -ForegroundColor DarkCyan
    $cmds | Format-Table Name, Source -AutoSize
}

# 7) Sanity check reports folder
$reports = Join-Path $root 'reports'
if (-not (Test-Path $reports)) {
    if ($Fix) {
        New-Item -ItemType Directory -Path $reports -Force | Out-Null
        Write-Host "Created reports folder: $reports" -ForegroundColor Green
    } else {
        $issues += "Missing reports folder: $reports"
    }
}

# 8) Summary
if ($issues.Count -eq 0) {
    Write-Host "`nAll checks passed ✅" -ForegroundColor Green
} else {
    Write-Host "`nIssues found:" -ForegroundColor Yellow
    $issues | ForEach-Object { " - $_" }
    if (-not $Fix) {
        Write-Host "`nRe-run with -Fix to auto-apply safe corrections:" -ForegroundColor Yellow
        Write-Host "  .\Diagnose-Playbook.ps1 -Fix"
    }
}
