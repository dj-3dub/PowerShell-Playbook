# tests/Reports.Tests.ps1
# Purpose: Validate that HTML/CSV reports are produced to a real path.

BeforeAll {
  $root = Split-Path -Parent $PSCommandPath
  $repo = Split-Path -Parent $root
  $manifest = Join-Path $repo 'src\PowerShellPlaybook.psd1'

  if (-not (Test-Path $manifest)) {
    throw "Module manifest not found at: $manifest"
  }

  Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
  Import-Module $manifest -Force

  $script:reports = Join-Path $repo 'reports'
  New-Item -ItemType Directory -Force -Path $script:reports | Out-Null
}

Describe 'Report generators' {
  It 'creates Conditional Access HTML (mock ok)' {
    $out = Get-ConditionalAccessReport -Environment Dev -OutputPath $script:reports -Verbose:($false)
    # Function returns path or object; assert the file exists
    # Try to discover the newest CA html in reports:
    $html = Get-ChildItem $script:reports -Filter 'ConditionalAccess-*.html' | Sort-Object LastWriteTime -Desc | Select-Object -First 1
    $html | Should -Not -BeNullOrEmpty
    Test-Path $html.FullName | Should -BeTrue
  }

  It 'creates Local Admin report HTML (mock ok on non-domain)' {
    $null = Get-LocalAdminReport -OutputPath $script:reports -Verbose:($false)
    $html = Get-ChildItem $script:reports -Filter 'LocalAdmins-*.html' | Sort-Object LastWriteTime -Desc | Select-Object -First 1
    $html | Should -Not -BeNullOrEmpty
    Test-Path $html.FullName | Should -BeTrue
  }

  It 'creates Certificate Expiry HTML (mock ok on non-Windows too)' {
    $null = Get-CertificateExpiry -Days 60 -OutputPath $script:reports -Verbose:($false)
    $html = Get-ChildItem $script:reports -Filter 'CertExpiry-*.html' | Sort-Object LastWriteTime -Desc | Select-Object -First 1
    $html | Should -Not -BeNullOrEmpty
    Test-Path $html.FullName | Should -BeTrue
  }
}
