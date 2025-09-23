# Safe-MakeExportsWildcard.ps1
$psd1 = "src/EnterpriseOpsToolkit.psd1"
$data = Import-PowerShellDataFile $psd1

$vars    = if ($null -ne $data.VariablesToExport) { $data.VariablesToExport } else { @('*') }
$aliases = if ($null -ne $data.AliasesToExport)   { $data.AliasesToExport }   else { @('*') }
$cmdlets = if ($null -ne $data.CmdletsToExport)   { $data.CmdletsToExport }   else { @() }

Update-ModuleManifest -Path $psd1 `
  -FunctionsToExport '*' `
  -CmdletsToExport $cmdlets `
  -VariablesToExport $vars `
  -AliasesToExport $aliases
