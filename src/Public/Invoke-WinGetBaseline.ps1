function Invoke-WinGetBaseline {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [string[]]$Packages=@("Microsoft.WindowsTerminal","7zip.7zip","Git.Git"),
    [switch]$Apply
  )
  if (-not $IsWindows) { return }

  $winget=Get-Command winget -ErrorAction SilentlyContinue
  if(-not $winget){ return }

  foreach($pkg in $Packages){
    $installed=winget list --id $pkg 2>$null
    if($installed){
      Write-Information "[OK] $pkg already installed" -InformationAction Continue
    } else {
      if($Apply){
        if ($PSCmdlet.ShouldProcess($pkg,"winget install")) {
          winget install --id $pkg --accept-source-agreements --accept-package-agreements | Out-Host
        }
      } else {
        Write-Information "[AUDIT] Would install $pkg (use -Apply to install)" -InformationAction Continue
      }
    }
  }
}

