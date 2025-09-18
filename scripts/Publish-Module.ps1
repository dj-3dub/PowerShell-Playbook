
param(
    [string]$OutDir = "./out"
)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$manifest = Join-Path $PSScriptRoot "..\src\EnterpriseOpsToolkit.psd1"
Copy-Item -Path $manifest -Destination (Join-Path $OutDir "EnterpriseOpsToolkit.psd1") -Force
Copy-Item -Path (Join-Path $PSScriptRoot "..\src\*.psm1") -Destination $OutDir -Force
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "Public") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "Private") | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot "..\src\Public\*.ps1") -Destination (Join-Path $OutDir "Public") -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "..\src\Private\*.ps1") -Destination (Join-Path $OutDir "Private") -Recurse -Force
Write-Host "Module staged at $OutDir"
