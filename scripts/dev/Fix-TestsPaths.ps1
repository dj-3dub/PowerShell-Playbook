$tests = @{
  'tests/ModuleLoad.Tests.ps1' = @'
# Verifies module loads and core commands are exported
$root    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
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
'@

  'tests/Reports.Tests.ps1' = @'
# Cross-platform: generates HTML into ./reports using mock config
$root    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$reports = Join-Path $root "reports"
$cfgDir  = Join-Path $root "src/config"
$cfgPath = Join-Path $cfgDir "dev.json"
$manifest = Join-Path $root 'src/EnterpriseOpsToolkit.psd1'

BeforeAll {
    New-Item -ItemType Directory -Force -Path $reports | Out-Null
    New-Item -ItemType Directory -Force -Path $cfgDir  | Out-Null
    if (-not (Test-Path $cfgPath)) {
        @'
{
  "UseMockData": true,
  "TenantName": "Contoso",
  "ReportBranding": { "TitlePrefix": "PowerShell Automation Toolkit", "Author": "Tim Heverin" }
}
'@ | Out-File $cfgPath -Encoding UTF8
    }
    Import-Module $manifest -Force
}

Describe "Report generation (mock)" {
    It "writes Conditional Access report HTML" {
        Get-ConditionalAccessReport -Environment Dev -OutputPath $reports
        (Get-ChildItem $reports -Filter *Conditional* -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }

    It "writes Exchange hygiene report HTML" {
        Get-ExchangeHygieneReport -Environment Dev -OutputPath $reports
        (Get-ChildItem $reports -Filter *Exchange* -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }
}
'@

  'tests/WindowsOnly.Tests.ps1' = @'
# Windows-only commands should no-op on non-Windows; assert no throws.
$root    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$reports = Join-Path $root "reports"
$manifest = Join-Path $root 'src/EnterpriseOpsToolkit.psd1'

BeforeAll {
    Import-Module $manifest -Force
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
'@

  'tests/Manifest.Tests.ps1' = @'
# Ensures manifest points to the psm1 and has sane metadata
$root  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$psd1  = Join-Path $root "src/EnterpriseOpsToolkit.psd1"

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
'@
}

foreach ($kvp in $tests.GetEnumerator()) {
  Set-Content -Path $kvp.Key -Value $kvp.Value -Encoding UTF8
  Write-Host "Wrote $($kvp.Key)"
}

# Optional: suppress 'unapproved verbs' message only during tests run
# (Your repo can keep the Invoke-Win11Debloat name; this just avoids noise in CI output.)
$psd1 = 'src/EnterpriseOpsToolkit.psd1'
if (Test-Path $psd1) {
  $data = Import-PowerShellDataFile $psd1
  # No change to the manifest; message is harmless. Left here as a reminder.
  Write-Host "Note: 'Invoke-Win11Debloat' uses an unapproved verb; safe to ignore during tests." -ForegroundColor Yellow
}

