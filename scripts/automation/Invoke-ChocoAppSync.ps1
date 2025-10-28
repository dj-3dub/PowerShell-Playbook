<#
.SYNOPSIS
  Ensures Chocolatey is present, upgrades all packages, and optionally installs from packages.config.
.PARAMETER PackagesConfig
  Path to a packages.config file to ensure installed.
.PARAMETER ForceInstallChoco
  Reinstall Chocolatey if already present.
.EXAMPLE
  .\Invoke-ChocoAppSync.ps1 -PackagesConfig .\packages.config -Verbose
#>
[CmdletBinding()]
param(
  [string]$PackagesConfig = ".\packages.config",
  [switch]$ForceInstallChoco
)

$global:chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"

function Install-Chocolatey {
  if (Test-Path $global:chocoExe -and -not $ForceInstallChoco) {
    Write-Verbose "Chocolatey already installed."
    return
  }
  Write-Host "Installing Chocolatey..."
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

function Choco {
  param([string]$Args)
  & $global:chocoExe $Args --no-progress -y | Write-Output
}

Install-Chocolatey

Write-Host "Upgrading all Chocolatey packages..."
Choco "upgrade all"

if (Test-Path $PackagesConfig) {
  Write-Host "Ensuring packages in $PackagesConfig are installed..."
  Choco "install $PackagesConfig"
} else {
  Write-Verbose "No packages.config found at $PackagesConfig"
}

Write-Host "Chocolatey sync complete."
