[CmdletBinding()]
param(
  [string]$RepoRoot = ".",
  [string]$Manifest = "src/EnterpriseOpsToolkit.psd1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Safe-Rename {
  param([string]$Old,[string]$New)
  if (Test-Path $Old) {
    Rename-Item -Path $Old -NewName (Split-Path -Leaf $New) -Force
    Write-Host "Renamed: $Old -> $New" -ForegroundColor Green
  } else {
    Write-Host "Skip rename (missing): $Old" -ForegroundColor Yellow
  }
}

function Replace-InFiles {
  param([string[]]$Paths,[hashtable]$Map)
  foreach ($p in $Paths) {
    if (-not (Test-Path $p)) { continue }
    $text = Get-Content $p -Raw
    $orig = $text
    foreach ($k in $Map.Keys) {
      $v = $Map[$k]
      $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $v)
    }
    if ($text -ne $orig) {
      Set-Content -Path $p -Value $text -Encoding UTF8
      Write-Host "Updated refs in: $p" -ForegroundColor Cyan
    }
  }
}

function Update-Manifest-Exports {
  param([string]$Psd1, [string[]]$Exports)
  $data = Import-PowerShellDataFile $Psd1
  if ($data.FunctionsToExport -eq '*') {
    Write-Host "Manifest already exports * ; leaving as-is." -ForegroundColor Yellow
    return
  }
  Update-ModuleManifest -Path $Psd1 -FunctionsToExport $Exports
  Write-Host "Manifest FunctionsToExport updated." -ForegroundColor Green
}

Push-Location $RepoRoot

# --- 0) Define new public function names (FINAL) ---
$PublicExports = @(
  'Get-ConditionalAccessReport',
  'Invoke-IntuneBaseline',
  'Get-ExchangeHygieneReport',
  'Invoke-Win11Debloat',
  'Get-LocalAdminReport',
  'Get-CertificateExpiry',
  'Get-DefenderStatus',
  'Invoke-WinGetBaseline',
  'Collect-SupportBundle'
)

# --- 1) Rename remaining files ---
# Windows script -> approved verb
Safe-Rename -Old "scripts/Invoke-Win11Debloat.ps1" -New "scripts/Invoke-Win11Debloat.ps1"

# Private logger file -> neutral name
Safe-Rename -Old "src/Private/Write-ToolkitLog.ps1" -New "src/Private/Write-ToolkitLog.ps1"

# --- 2) Replace symbol names across repo ---
$replaceMap = @{
  # function/cmd names
  'Invoke-Win11Debloat'                = 'Invoke-Win11Debloat'
  'Get-ConditionalAccessReport' = 'Get-ConditionalAccessReport'
  'Invoke-IntuneBaseline'     = 'Invoke-IntuneBaseline'
  'Get-ExchangeHygieneReport'       = 'Get-ExchangeHygieneReport'
  'Get-LocalAdminReport'      = 'Get-LocalAdminReport'
  'Get-CertificateExpiry'     = 'Get-CertificateExpiry'
  'Get-DefenderStatus'        = 'Get-DefenderStatus'
  'Invoke-WinGetBaseline'     = 'Invoke-WinGetBaseline'
  'Collect-SupportBundle'     = 'Collect-SupportBundle'
  # private logger
  'Write-ToolkitLog'                 = 'Write-ToolkitLog'
}

$allTextFiles = Get-ChildItem -Recurse -File -Include *.ps1,*.psm1,*.psd1,*.md | Select-Object -ExpandProperty FullName
Replace-InFiles -Paths $allTextFiles -Map $replaceMap

# --- 3) Ensure private logger function is renamed inside file (in case dot-sourced) ---
if (Test-Path "src/Private/Write-ToolkitLog.ps1") {
  $f = Get-Content "src/Private/Write-ToolkitLog.ps1" -Raw
  $f = [regex]::Replace($f, '(?m)^\s*function\s+Write-ToolkitLog\b', 'function Write-ToolkitLog')
  Set-Content -Path "src/Private/Write-ToolkitLog.ps1" -Value $f -Encoding UTF8
}

# --- 4) Normalize config filename (case) ---
if (Test-Path "src/config/Dev.json") {
  Remove-Item "src/config/Dev.json" -Force
  Write-Host "Removed duplicate src/config/Dev.json (kept dev.json)" -ForegroundColor Green
}
if (Test-Path "config/debloat-appx.json") {
  # keep as-is; used by debloat script
}

# --- 5) Update manifest exports ---
Update-Manifest-Exports -Psd1 $Manifest -Exports $PublicExports

# --- 6) Remove legacy test file that referenced old names, if present ---
if (Test-Path "tests/EnterpriseOpsToolkit.Tests.ps1") {
  Remove-Item "tests/EnterpriseOpsToolkit.Tests.ps1" -Force
  Write-Host "Removed legacy tests/EnterpriseOpsToolkit.Tests.ps1" -ForegroundColor Green
}

Pop-Location
Write-Host "`nFinalize-Renames complete." -ForegroundColor Cyan

