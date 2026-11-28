function Invoke-WinGetBaseline {
  <#
  .SYNOPSIS
  Audits (default) or installs (-Apply) a baseline set of WinGet packages on the local machine.

  .PARAMETER Packages
  WinGet package IDs. Default: Microsoft.WindowsTerminal, 7zip.7zip, Git.Git.

  .PARAMETER Apply
  Install missing packages (supports -WhatIf). Without it, missing packages are only reported.

  .EXAMPLE
  Invoke-WinGetBaseline -Packages Microsoft.PowerShell, Git.Git -Apply -WhatIf
  #>
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [string[]]$Packages=@("Microsoft.WindowsTerminal","7zip.7zip","Git.Git"),
    [switch]$Apply
  )
  # $IsWindows does not exist on Windows PowerShell 5.1 (which is always Windows).
  if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { return }

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

