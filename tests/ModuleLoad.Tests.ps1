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
# Verifies module loads and core commands are exported
$root     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manifest = Join-Path $root 'src/EnterpriseOpsToolkit.psd1'

Describe "Module loads and commands are exported" {
    It "imports the module without error" {
        { Import-Module $manifest -Force -ErrorAction Stop } | Should -Not -Throw
    }

    $expected = @(
        'Get-ConditionalAccessReport',
        'Get-ExchangeHygieneReport',
        'Invoke-IntuneBaseline',
        'Invoke-Win11Debloat',
        'Get-LocalAdminReport',
        'Get-CertificateExpiry',
        'Get-DefenderStatus',
        'Invoke-WinGetBaseline',
        'Collect-SupportBundle'
    )

    It "exports the expected functions (at least these)" {
        $cmds = (Get-Command -Module EnterpriseOpsToolkit).Name
        foreach ($f in $expected) { $cmds | Should -Contain $f }
    }
}




