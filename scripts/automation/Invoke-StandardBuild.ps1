<#
.SYNOPSIS
    Installs a standard software build on a Windows machine.

.DESCRIPTION
    Reads a JSON config file defining your standard applications and installs
    them via Winget (default) or Chocolatey. Logs results to the exports folder.

.PARAMETER ConfigPath
    Path to the JSON config. Default: .\config\software-build.json

.PARAMETER Provider
    Package provider to use: 'winget' or 'choco'. If omitted, the config's
    PackageProvider is used, defaulting to 'winget'.

.EXAMPLE
    .\Invoke-StandardBuild.ps1

.EXAMPLE
    .\Invoke-StandardBuild.ps1 -ConfigPath .\config\lab-build.json -Provider choco -Verbose
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path (Join-Path $PSScriptRoot '..\..') 'config\software-build.json'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('winget', 'choco')]
    [string]$Provider
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BuildConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Config file not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw
    $cfg = $raw | ConvertFrom-Json

    if (-not $cfg.Applications) {
        throw "Config '$Path' has no 'Applications' array."
    }

    return $cfg
}

function Install-AppWinget {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Id
    )

    Write-Verbose "Installing '$Name' via winget ($Id)..."

    $arguments = @(
        'install',
        '--id', $Id,
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    $process = Start-Process -FilePath 'winget.exe' -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -eq 0) {
        return $true
    }

    Write-Warning "Winget install failed for '$Name' ($Id) with exit code $($process.ExitCode)."
    return $false
}

function Install-AppChoco {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Id
    )

    Write-Verbose "Installing '$Name' via Chocolatey ($Id)..."

    choco install $Id -y | Write-Verbose

    # naive success signal – can improve later
    return $true
}

$cfg = Get-BuildConfig -Path $ConfigPath

if (-not $Provider) {
    $Provider = if ($cfg.PackageProvider) { $cfg.PackageProvider } else { 'winget' }
}

Write-Verbose "Using provider: $Provider"
Write-Verbose "Applications: $($cfg.Applications.Count)"

$results = foreach ($app in $cfg.Applications) {
    $name = $app.Name
    $id   = $app.Id

    if (-not $name -or -not $id) {
        Write-Warning "Skipping invalid app entry: $($app | ConvertTo-Json -Compress)"
        continue
    }

    try {
        $success = switch ($Provider) {
            'winget' { Install-AppWinget -Name $name -Id $id }
            'choco'  { Install-AppChoco  -Name $name -Id $id }
        }

        [pscustomobject]@{
            Application = $name
            Id          = $id
            Provider    = $Provider
            Succeeded   = $success
        }
    }
    catch {
        Write-Warning "Failed installing '$name' ($id): $_"
        [pscustomobject]@{
            Application = $name
            Id          = $id
            Provider    = $Provider
            Succeeded   = $false
        }
    }
}

if ($results) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outDir    = Join-Path (Join-Path $PSScriptRoot '..\..') 'exports'
    $null      = New-Item -Path $outDir -ItemType Directory -Force -ErrorAction SilentlyContinue
    $report    = Join-Path $outDir "StandardBuild-$timestamp.csv"

    $results | Export-Csv -Path $report -NoTypeInformation -Encoding UTF8
    Write-Host "Standard build completed. Report: $report" -ForegroundColor Green
}
else {
    Write-Host "No applications were processed." -ForegroundColor Yellow
}
