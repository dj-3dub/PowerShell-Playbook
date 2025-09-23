# --- Standard Pester bootstrap (per-file, per-runspace) ---
BeforeAll {
  # Resolve paths relative to this test file
  $here    = Split-Path -Parent $PSCommandPath
  $root    = Split-Path -Parent $here
  $psd1    = Join-Path $root 'src/PowerShellPlaybook.psd1'
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
$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'src/PowerShellPlaybook.psd1'
$psd1 = $manifest  # some tests refer to $psd1

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
# These scripts are Windows-only at runtime. On non-Windows we assert they "no-op" without throwing.
$here = Split-Path -Parent $PSCommandPath
$root = Resolve-Path "$here/.."
$reports = Join-Path $root "reports"

BeforeAll {
    Import-Module "$root/src/PowerShellPlaybook.psd1" -Force
    New-Item -ItemType Directory -Force -Path $reports | Out-Null
}

Describe "Windows-only commands behave" {
    It "Get-DefenderStatus does not throw" {
        { Get-DefenderStatus -OutputPath $reports } | Should -Not -Throw
    }
    It "Invoke-WinGetBaseline audits or installs without throwing" {
        { Invoke-WinGetBaseline } | Should -Not -Throw
    }
    It "Collect-SupportBundle creates or skips without throwing" {
        { Collect-SupportBundle -Hours 1 -OutputPath $reports } | Should -Not -Throw
    }

    Context "On Windows only" -Skip:(-not $IsWindows) {
        It "Defender report file exists" {
            Get-DefenderStatus -OutputPath $reports
            (Get-ChildItem $reports -Filter *DefenderStatus*).Count | Should -BeGreaterThan 0
        }
    }
}




