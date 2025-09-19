[CmdletBinding(SupportsShouldProcess)]
param([string[]]$Packages=@("Microsoft.WindowsTerminal","7zip.7zip","Git.Git"),[switch]$Apply)
$winget=Get-Command winget -ErrorAction SilentlyContinue
if(-not $winget){Write-Warning "winget not found. Skipping.";return}
foreach($pkg in $Packages){
 $installed=winget list --id $pkg 2>$null
 if($installed){Write-Host "[OK] $pkg already installed"}else{
  if($Apply -and $PSCmdlet.ShouldProcess($pkg,"winget install")){
   winget install --id $pkg --accept-source-agreements --accept-package-agreements|Out-Host
  }else{Write-Host "[AUDIT] Would install $pkg (use -Apply to install)"}
 }}
