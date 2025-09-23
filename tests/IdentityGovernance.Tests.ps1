# Identity Governance (mock-friendly)

BeforeAll {
  $root     = Split-Path -Parent $PSScriptRoot
  $manifest = Join-Path $root 'src/EnterpriseOpsToolkit.psd1'
  if (-not (Test-Path $manifest)) { throw "Module manifest not found at: $manifest" }

  $reports  = Join-Path $root 'reports'
  $outdir   = Join-Path $root 'out'
  New-Item -ItemType Directory -Force -Path $reports,$outdir | Out-Null

  Import-Module $manifest -Force

  Set-Variable -Name reports -Value $reports -Scope Script
  Set-Variable -Name outdir  -Value $outdir  -Scope Script
}

Describe 'Identity Governance' {
  It 'Produces an inactive accounts report (mock on Linux)' {
    $path = Get-InactiveAdAccounts -DaysInactive 60 -OutputPath $script:reports
    $path | Should -Not -BeNullOrEmpty
    Test-Path $path | Should -BeTrue
  }

  It 'Builds password expiry notifications in Preview mode' {
    $path = Send-PasswordExpiryNotifications -Days 14 -Preview -OutputPath $script:outdir
    $path | Should -Not -BeNullOrEmpty
    Test-Path $path | Should -BeTrue
  }
}
