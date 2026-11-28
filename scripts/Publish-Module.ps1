<#
.SYNOPSIS
    Stage the PowerShellPlaybook module into a self-contained folder ready for
    Publish-Module / Install-Module or copying onto a machine's PSModulePath.

.EXAMPLE
    ./scripts/Publish-Module.ps1 -OutDir ./out
    Import-Module ./out/PowerShellPlaybook -Force
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'out')
)

$ErrorActionPreference = 'Stop'

$src    = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$target = Join-Path $OutDir 'PowerShellPlaybook'

if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Force -Path $target | Out-Null

Copy-Item -Path (Join-Path $src 'PowerShellPlaybook.psd1') -Destination $target
Copy-Item -Path (Join-Path $src 'PowerShellPlaybook.psm1') -Destination $target
foreach ($dir in 'Public', 'Private', 'Shared', 'config') {
    Copy-Item -Path (Join-Path $src $dir) -Destination $target -Recurse
}

Test-ModuleManifest -Path (Join-Path $target 'PowerShellPlaybook.psd1') | Out-Null
Write-Host "Module staged at $target"
