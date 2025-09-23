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
# === Robust repo root resolution ===
# Prefer env var from the runner; fall back to current working directory.
$root = $env:REPO_ROOT
if (-not $root) { $root = (Resolve-Path (Get-Location)).Path }
# Ensures manifest points to the psm1 and has sane metadata
$here = Split-Path -Parent $PSCommandPath
$root = Resolve-Path "$here/.."
$psd1 = Join-Path $root "src/EnterpriseOpsToolkit.psd1"

Describe "Module manifest" {
    It "exists" {
        Test-Path $psd1 | Should -BeTrue
    }

    It "RootModule points to the psm1" {
        $data = Import-PowerShellDataFile $psd1
        (Join-Path (Split-Path $psd1) $data.RootModule) | Should -Exist
    }

    It "FunctionsToExport is array or '*'" {
        $data = Import-PowerShellDataFile $psd1
        ($data.FunctionsToExport -eq '*') -or ($data.FunctionsToExport -is [System.Array]) | Should -BeTrue
    }
}




