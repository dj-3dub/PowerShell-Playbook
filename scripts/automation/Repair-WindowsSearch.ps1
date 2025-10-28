<#
.SYNOPSIS
  Repairs common Windows Search issues (service, index, system files).
.PARAMETER ResetIndex
  Stop Windows Search and rebuild the index.
.PARAMETER RunSfc
  Run SFC /SCANNOW to repair system files.
.PARAMETER RunDism
  Run DISM /Online /Cleanup-Image /RestoreHealth.
.EXAMPLE
  .\Repair-WindowsSearch.ps1 -ResetIndex -RunSfc -RunDism -Verbose
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$ResetIndex,
  [switch]$RunSfc,
  [switch]$RunDism
)

function Ensure-ServiceRunning {
  $svc = Get-Service -Name WSearch -ErrorAction SilentlyContinue
  if (-not $svc) { Write-Warning "WSearch service not found."; return }
  if ($svc.Status -ne 'Running') {
    Start-Service -Name WSearch -ErrorAction SilentlyContinue
    $svc.WaitForStatus('Running','00:00:10')
  }
}

if ($ResetIndex) {
  if ($PSCmdlet.ShouldProcess("Windows Search","Reset Index")) {
    Write-Verbose "Restarting WSearch service..."
    try {
      Stop-Service WSearch -Force -ErrorAction SilentlyContinue
    } catch {}
    $indexPath = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows"
    $edb = Join-Path $indexPath "Windows.edb"
    if (Test-Path $edb) {
      Rename-Item $edb "$($edb).bak-$(Get-Date -Format yyyyMMddHHmmss)" -Force
      Write-Host "Index database renamed; Windows will rebuild the index."
    }
    Ensure-ServiceRunning
  }
}

if ($RunSfc) {
  if ($PSCmdlet.ShouldProcess("System Files","SFC")) {
    sfc /scannow
  }
}

if ($RunDism) {
  if ($PSCmdlet.ShouldProcess("Component Store","DISM RestoreHealth")) {
    DISM /Online /Cleanup-Image /RestoreHealth
  }
}

if (-not ($ResetIndex -or $RunSfc -or $RunDism)) {
  Write-Host "Nothing selected. Use -ResetIndex, -RunSfc, -RunDism."
}
