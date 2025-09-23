<#
.SYNOPSIS
Lint & test runner for PowerShell Playbook (Pester 5+).

.PARAMETER InstallTools
Install/update Pester and PSScriptAnalyzer for the current user.

.PARAMETER Output
Console verbosity: None | Minimal | Normal | Detailed | Diagnostics  (Default: Detailed)

.PARAMETER NUnitXml
Write NUnit-style results to this file (e.g. .\test-results.xml).
#>

[CmdletBinding()]
param(
    [switch]$InstallTools,
    [ValidateSet('None', 'Minimal', 'Normal', 'Detailed', 'Diagnostics')]
    [string]$Output = 'Detailed',
    [string]$NUnitXml
)

$ErrorActionPreference = 'Stop'

# --- Resolve repo root robustly
# Works whether invoked from root or elsewhere, and in PS 5.1/7+
$scriptPath = $MyInvocation.MyCommand.Path
if (-not $scriptPath) { $scriptPath = $PSCommandPath }  # fallback for PS7
$root = Split-Path -Parent $scriptPath

Write-Host "=== PowerShell Playbook: Lint & Test ==="
Write-Host "Root: $root"
Write-Host "PS: $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
Write-Host ""

# --- Helper to ensure tools
function Ensure-Module {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$MinimumVersion
    )
    if (-not $InstallTools) { return }
    $have = Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $have -or ($MinimumVersion -and ([version]$have.Version -lt [version]$MinimumVersion))) {
        Write-Host "Installing $Name (min $MinimumVersion) for current user..."
        $p = @{ Name = $Name; Scope = 'CurrentUser'; Force = $true }
        if ($MinimumVersion) { $p.MinimumVersion = $MinimumVersion }
        Install-Module @p -AllowClobber -ErrorAction Stop
    } else {
        Write-Host "$Name already installed (v$($have.Version))."
    }
}

# Optionally install/update tools
Ensure-Module -Name 'Pester' -MinimumVersion '5.4.0'
Ensure-Module -Name 'PSScriptAnalyzer' -MinimumVersion '1.21.0'

# --- Lint if PSScriptAnalyzer is available
$analyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1
if ($analyzer) {
    Write-Host "`nLinting with PSScriptAnalyzer ($($analyzer.Version))..."
    try {
        Invoke-ScriptAnalyzer -Path (Join-Path $root 'src') -Recurse -Severity Warning -ReportSummary
    } catch {
        Write-Warning "ScriptAnalyzer failed: $($_.Exception.Message)"
    }
} else {
    Write-Host "PSScriptAnalyzer not available. Skipping lint."
}

# --- Import module under test (helps Pester discovery)
$manifest = Join-Path $root 'src\PowerShellPlaybook.psd1'
if (Test-Path $manifest) {
    try {
        Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
        Import-Module $manifest -Force -ErrorAction Stop
        Write-Host "Imported module: PowerShellPlaybook"
    } catch {
        Write-Warning "Module import warning: $($_.Exception.Message)"
    }
} else {
    Write-Warning "Module manifest not found at $manifest"
}

# --- Build and run Pester 5 configuration
$testPath = Join-Path $root 'tests'
Import-Module Pester -Force

# Use New-PesterConfiguration (v5) to avoid type load issues
$cfg = New-PesterConfiguration
$cfg.Run.Path = $testPath
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = $Output     # None/Minimal/Normal/Detailed/Diagnostics
$cfg.TestResult.Enabled = $false

if ($NUnitXml) {
    # Resolve if possible; else let Pester create it
    try {
        $resolved = Resolve-Path -Path $NUnitXml -ErrorAction Stop
        $cfg.TestResult.OutputPath = $resolved.ProviderPath
    } catch {
        $cfg.TestResult.OutputPath = $NUnitXml
    }
    $cfg.TestResult.Enabled = $true
    $cfg.TestResult.OutputFormat = 'NUnitXml'
    Write-Host "NUnit XML -> $($cfg.TestResult.OutputPath)"
}

Write-Host "`nRunning Pester..."
$results = Invoke-Pester -Configuration $cfg

Write-Host ""
Write-Host "Passed: $($results.PassedCount)  Failed: $($results.FailedCount)  Skipped: $($results.SkippedCount)"
if ($results.FailedCount -gt 0) { exit 1 } else { exit 0 }
