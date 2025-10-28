<#
.SYNOPSIS
  Resets Windows Update components and optionally kicks off a scan/install.
.PARAMETER Scan
  After reset, start a scan for updates.
.PARAMETER Install
  After scan, install available updates (reboots may be required).
.EXAMPLE
  .\Repair-WindowsUpdate.ps1 -Scan -Verbose
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$Scan,
  [switch]$Install
)

function Stop-WuServices {
  'wuauserv','bits','cryptsvc','dosvc' | ForEach-Object {
    $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
      Write-Verbose "Stopping service $_"
      Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
    }
  }
}

function Start-WuServices {
  'cryptsvc','bits','wuauserv','dosvc' | ForEach-Object {
    $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
      Write-Verbose "Starting service $_"
      Start-Service -Name $_ -ErrorAction SilentlyContinue
    }
  }
}

function Reset-Folders {
  $paths = @(
    "$env:SystemRoot\SoftwareDistribution",
    "$env:SystemRoot\System32\catroot2"
  )
  foreach ($p in $paths) {
    if (Test-Path $p) {
      Write-Verbose "Clearing $p"
      Remove-Item "$p\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Invoke-UpdateCycle {
  try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    Write-Verbose "Searching for updates..."
    $result = $searcher.Search("IsInstalled=0 and Type='Software'")
    if ($result.Updates.Count -eq 0) {
      Write-Host "No updates found."
      return
    }
    Write-Host "Found $($result.Updates.Count) updates."
    if ($Install) {
      $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
      $result.Updates | ForEach-Object { [void]$toInstall.Add($_) }
      $installer = $session.CreateUpdateInstaller()
      $installer.Updates = $toInstall
      Write-Verbose "Installing updates..."
      $result2 = $installer.Install()
      Write-Host "Install result: $($result2.ResultCode)  RebootRequired=$($result2.RebootRequired)"
    }
  } catch {
    Write-Warning "Unable to search/install updates via COM: $($_.Exception.Message)"
  }
}

if ($PSCmdlet.ShouldProcess("Windows Update Components","Reset")) {
  Stop-WuServices
  Reset-Folders
  Start-WuServices
  Write-Host "Windows Update components reset."
  if ($Scan) { Invoke-UpdateCycle }
}
