# Make-ExportsWildcard.ps1 (one-time)
$psd1 = "src/EnterpriseOpsToolkit.psd1"
$data = Import-PowerShellDataFile $psd1
Update-ModuleManifest -Path $psd1 -FunctionsToExport '*' -CmdletsToExport @() -VariablesToExport @() -AliasesToExport @()
(Get-Content $psd1 -Raw) -replace "FunctionsToExport\s*=\s*@\([^\)]*\)","FunctionsToExport = '*'" |
  Set-Content $psd1 -Encoding UTF8
Write-Host "Manifest updated to export *"
