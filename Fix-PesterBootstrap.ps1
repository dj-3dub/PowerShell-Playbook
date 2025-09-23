# Fix-PesterBootstrap.ps1
$ErrorActionPreference = 'Stop'

$bootstrap = @'
# --- Standard Pester bootstrap (per-file, per-runspace) ---
BeforeAll {
  # Resolve paths relative to this test file
  $here    = Split-Path -Parent $PSCommandPath
  $root    = Split-Path -Parent $here
  $psd1    = Join-Path $root 'src/EnterpriseOpsToolkit.psd1'
  $reports = Join-Path $root 'reports'
  $outdir  = Join-Path $root 'out'

  if (-not (Test-Path $psd1)) { throw "Module manifest not found at: $psd1" }

  # Ensure output folders exist for tests that write files
  New-Item -ItemType Directory -Force -Path $reports,$outdir | Out-Null

  # Import the module for this runspace
  Import-Module $psd1 -Force

  # Expose commonly-used vars so existing tests referencing $psd1/$reports/$root work
  Set-Variable -Name psd1    -Value $psd1   -Scope Global
  Set-Variable -Name reports -Value $reports -Scope Global
  Set-Variable -Name root    -Value $root    -Scope Global
}
'@

Get-ChildItem tests -Filter *.ps1 | ForEach-Object {
  $path = $_.FullName
  $orig = Get-Content $path -Raw

  # If it already contains our marker, skip
  if ($orig -match 'Standard Pester bootstrap') {
    Write-Host "OK  : $($_.Name) already bootstrapped"
  } else {
    # Prepend the bootstrap so variables exist before any Describe/It blocks
    Set-Content -Path $path -Value ($bootstrap + "`n" + $orig) -Encoding UTF8
    Write-Host "FIX : Prepended bootstrap to $($_.Name)"
  }
}

# Ensure manifest exports '*' so new public scripts are visible
$psd1Path = 'src/EnterpriseOpsToolkit.psd1'
$data     = Import-PowerShellDataFile $psd1Path
if ($data.FunctionsToExport -ne '*') {
  Write-Host "Updating FunctionsToExport='*' in manifest..."
  $content = (Get-Content $psd1Path -Raw) -replace 'FunctionsToExport\s*=\s*@\([^\)]*\)', "FunctionsToExport = '*'"
  Set-Content $psd1Path -Value $content -Encoding UTF8
}
Write-Host "Done."
