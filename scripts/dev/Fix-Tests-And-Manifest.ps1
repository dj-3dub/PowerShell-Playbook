# Fix-Tests-And-Manifest.ps1
$ErrorActionPreference = 'Stop'

# --- Ensure manifest exports '*' so any src/Public/*.ps1 is available ---
$psd1 = "src/EnterpriseOpsToolkit.psd1"
$data = Import-PowerShellDataFile $psd1
if ($data.FunctionsToExport -ne '*') {
  Write-Host "Setting FunctionsToExport='*' in manifest..." -ForegroundColor Yellow
  $content = Get-Content $psd1 -Raw
  if ($content -match 'FunctionsToExport\s*=\s*@\([^\)]*\)') {
    $content = $content -replace 'FunctionsToExport\s*=\s*@\([^\)]*\)', "FunctionsToExport = '*'"
  } elseif ($content -match 'FunctionsToExport\s*=\s*".*?"') {
    $content = $content -replace 'FunctionsToExport\s*=\s*".*?"', "FunctionsToExport = '*'"
  } else {
    # append if key missing
    $content = $content -replace '^\s*PrivateData\s*=\s*@\{','FunctionsToExport = ''*''`nPrivateData = @{'
  }
  Set-Content $psd1 -Value $content -Encoding UTF8
}

# Helper to safely rewrite a test file header to resolve paths + import module
function Fix-TestHeader {
  param([string]$Path)

  $newHeader = @'
# --- Standard test bootstrap: resolve repo root + import module ---
$here = Split-Path -Parent $PSCommandPath
$root = (Resolve-Path (Join-Path $here '..')).Path
$manifest = Join-Path $root 'src/EnterpriseOpsToolkit.psd1'

BeforeAll {
  if (-not (Test-Path $manifest)) {
    throw "Module manifest not found at: $manifest"
  }
  Import-Module $manifest -Force
}
'@

  $orig = Get-Content $Path -Raw
  # If file already has 'BeforeAll' that imports module, skip; else prepend header
  if ($orig -notmatch 'Import-Module\s+.*EnterpriseOpsToolkit\.psd1') {
    Set-Content $Path -Value ($newHeader + "`n" + $orig) -Encoding UTF8
    Write-Host "Patched: $Path"
  } else {
    Write-Host "Already imports module: $Path"
  }
}

# Patch all our test files
Get-ChildItem tests -Filter *.ps1 | ForEach-Object { Fix-TestHeader -Path $_.FullName }

Write-Host "Done patching tests and manifest." -ForegroundColor Green
