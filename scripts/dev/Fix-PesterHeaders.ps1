# Fix-PesterHeaders.ps1
$ErrorActionPreference = 'Stop'

$header = @'
# --- Standard test bootstrap: resolve repo root + import module ---
$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'src/EnterpriseOpsToolkit.psd1'
$psd1 = $manifest  # some tests refer to $psd1

BeforeAll {
  if (-not (Test-Path $manifest)) {
    throw "Module manifest not found at: $manifest"
  }
  Import-Module $manifest -Force
}
'@

Get-ChildItem -Path tests -Filter *.ps1 | ForEach-Object {
  $path = $_.FullName
  $orig = Get-Content $path -Raw

  # If it already imports the module via EnterpriseOpsToolkit.psd1, keep it
  if ($orig -match "EnterpriseOpsToolkit\.psd1") {
    # But still ensure $psd1/$manifest are defined; if not, prepend header
    if ($orig -notmatch '\$manifest\s*=.*EnterpriseOpsToolkit\.psd1' -and $orig -notmatch '\$psd1\s*=') {
      Set-Content -Path $path -Value ($header + "`n" + $orig) -Encoding UTF8
      Write-Host "Patched (prepended header): $path"
    } else {
      Write-Host "Already has a bootstrap: $path"
    }
  } else {
    Set-Content -Path $path -Value ($header + "`n" + $orig) -Encoding UTF8
    Write-Host "Patched (prepended header): $path"
  }
}

Write-Host "Done. Test headers standardized." -ForegroundColor Green
