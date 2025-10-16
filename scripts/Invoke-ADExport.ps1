<#
.SYNOPSIS
    Batch runner for Export-ADObjects-NoRSAT.ps1

.DESCRIPTION
    Runs multiple AD export jobs defined inline or in a JSON config file.
    Works with both real-domain and -Mock runs.

.EXAMPLE
    .\Invoke-ADExport.ps1 -Verbose
.EXAMPLE
    .\Invoke-ADExport.ps1 -ConfigPath .\ad-export.config.json -Verbose
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "./ad-export.config.json",
    [switch]$Mock,
    [int]$MockCount = 25
)

# Path to the exporter (same folder)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$exporter  = Join-Path $scriptDir "Export-ADObjects-NoRSAT.ps1"

if (-not (Test-Path $exporter)) {
    throw "Exporter script not found: $exporter"
}

# Default jobs (if no JSON present)
$jobs = @(
    @{
        ObjectType = "User"
        Filter     = "Enabled -eq `$true"
        OutputPath = "../exports/users_enabled.csv"
    },
    @{
        ObjectType = "Computer"
        Filter     = "*"
        OutputPath = "../exports/computers_all.csv"
    },
    @{
        ObjectType = "Group"
        Filter     = "*"
        OutputPath = "../exports/groups_all.csv"
    }
)

# Load from JSON if provided and exists
if (Test-Path $ConfigPath) {
    Write-Verbose "Loading job definitions from $ConfigPath"
    try {
        $configData = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        if ($configData.Jobs) { $jobs = $configData.Jobs }
    } catch {
        Write-Warning "Failed to parse config file. Using default jobs."
    }
}

# Run each job
foreach ($job in $jobs) {
    Write-Host "▶ Running $($job.ObjectType) export..." -ForegroundColor Cyan

    # renamed from $args → $jobArgs
    $jobArgs = @{
        ObjectType = $job.ObjectType
        Filter     = $job.Filter
        OutputPath = $job.OutputPath
        Verbose    = $true
    }

    if ($Mock) {
        $jobArgs.Mock = $true
        $jobArgs.MockCount = $MockCount
    }

    if ($job.SearchBase)  { $jobArgs.SearchBase  = $job.SearchBase }
    if ($job.Server)      { $jobArgs.Server      = $job.Server }
    if ($job.Credential)  { $jobArgs.Credential  = $job.Credential }
    if ($job.Properties)  { $jobArgs.Properties  = $job.Properties }
    if ($job.UseLDAPS)    { $jobArgs.UseLDAPS    = $true }
    if ($job.Port)        { $jobArgs.Port        = $job.Port }

    & $exporter @jobArgs
    Write-Host ""
}

Write-Host "✅ All jobs complete." -ForegroundColor Green
