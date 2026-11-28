<#
.SYNOPSIS
  Ensures Chocolatey is present, upgrades all packages, and optionally installs from a packages.config.

.DESCRIPTION
  1. Installs Chocolatey with the official bootstrap script if choco.exe is missing (or -ForceInstallChoco).
  2. Runs 'choco upgrade all'.
  3. If -PackagesConfig exists, runs 'choco install <file>' to ensure those packages are present.
  Requires an elevated session. Supports -WhatIf. Exits with choco's exit code on failure.

.PARAMETER PackagesConfig
  Path to a packages.config file to ensure installed.

.PARAMETER ForceInstallChoco
  Re-run the Chocolatey installer even if choco.exe is already present.

.EXAMPLE
  .\Invoke-ChocoAppSync.ps1 -PackagesConfig .\packages.config -Verbose

.EXAMPLE
  .\Invoke-ChocoAppSync.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$PackagesConfig = '.\packages.config',
  [switch]$ForceInstallChoco
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$chocoExe = Join-Path $env:ProgramData 'chocolatey\bin\choco.exe'

function Install-Chocolatey {
  if ((Test-Path $chocoExe) -and -not $ForceInstallChoco) {
    Write-Verbose 'Chocolatey already installed.'
    return
  }
  if (-not $PSCmdlet.ShouldProcess('Chocolatey', 'Install from community.chocolatey.org')) { return }

  Write-Host 'Installing Chocolatey...'
  # Official bootstrap (https://chocolatey.org/install). Organizations with an internal feed
  # should install from that instead of the public script.
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $installer = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')
  & ([scriptblock]::Create($installer))
}

function Invoke-Choco {
  # Pass arguments as an array so each becomes its own token (e.g. 'upgrade', 'all').
  param([Parameter(Mandatory)] [string[]]$ChocoArgs)
  $line = "choco $($ChocoArgs -join ' ')"
  if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, $line)) { return }

  & $chocoExe @ChocoArgs --no-progress -y
  # 0 = success; 1641/3010 = success, reboot required/initiated
  if ($LASTEXITCODE -notin 0, 1641, 3010) {
    Write-Error "$line failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
  }
}

Install-Chocolatey

Write-Host 'Upgrading all Chocolatey packages...'
Invoke-Choco -ChocoArgs 'upgrade', 'all'

if (Test-Path $PackagesConfig) {
  Write-Host "Ensuring packages in $PackagesConfig are installed..."
  Invoke-Choco -ChocoArgs 'install', (Resolve-Path $PackagesConfig).ProviderPath
}
else {
  Write-Verbose "No packages.config found at $PackagesConfig"
}

Write-Host 'Chocolatey sync complete.'
