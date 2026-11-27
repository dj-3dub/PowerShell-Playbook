<#
.SYNOPSIS
    Resets Windows Update components, and optionally scans for and installs updates.

.DESCRIPTION
    Standard Windows Update component reset:
      1. Stops wuauserv, bits, cryptsvc and dosvc (Delivery Optimization)
      2. Renames SoftwareDistribution and catroot2 to *.bak-<timestamp> (kept for rollback/forensics,
         rather than deleted outright)
      3. Restarts the services
    Then, optionally, scans via the Windows Update Agent (-Scan) and downloads + installs what it finds (-Install).

    Requires an elevated session. Supports -WhatIf / -Confirm.

.PARAMETER Scan
    After the reset, search for applicable software updates.

.PARAMETER Install
    Download and install the updates found by the scan (implies -Scan). A reboot may be required.

.EXAMPLE
    .\Repair-WindowsUpdate.ps1 -WhatIf

.EXAMPLE
    .\Repair-WindowsUpdate.ps1 -Install -Verbose
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Scan,
    [switch]$Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this script from an elevated PowerShell session.' }

$services = 'wuauserv', 'bits', 'cryptsvc', 'dosvc'
$folders  = (Join-Path $env:SystemRoot 'SoftwareDistribution'), (Join-Path $env:SystemRoot 'System32\catroot2')
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'

# 1) Stop services
foreach ($name in $services) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped' -and $PSCmdlet.ShouldProcess($name, 'Stop service')) {
        Write-Verbose "Stopping $name"
        Stop-Service -Name $name -Force
    }
}

# 2) Rename cache folders (Windows recreates them on service start)
foreach ($path in $folders) {
    if ((Test-Path $path) -and $PSCmdlet.ShouldProcess($path, "Rename to $(Split-Path $path -Leaf).bak-$stamp")) {
        Rename-Item -Path $path -NewName "$(Split-Path $path -Leaf).bak-$stamp"
        Write-Verbose "Renamed $path"
    }
}

# 3) Start services again (reverse dependency order)
[array]::Reverse($services)
foreach ($name in $services) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running' -and $svc.StartType -ne 'Disabled' -and $PSCmdlet.ShouldProcess($name, 'Start service')) {
        Write-Verbose "Starting $name"
        Start-Service -Name $name
    }
}
Write-Host 'Windows Update components reset.' -ForegroundColor Green

# 4) Optional scan / download / install
if ($Scan -or $Install) {
    $session = New-Object -ComObject Microsoft.Update.Session
    Write-Verbose 'Searching for updates...'
    $found = $session.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Software' and IsHidden=0").Updates
    Write-Host "Found $($found.Count) applicable update(s)."
    foreach ($u in $found) { Write-Host "  - $($u.Title)" }

    if ($Install -and $found.Count -gt 0 -and $PSCmdlet.ShouldProcess("$($found.Count) update(s)", 'Download and install')) {
        $batch = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $found) {
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            [void]$batch.Add($u)
        }

        # Updates must be downloaded before the installer will accept them.
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $batch
        Write-Verbose 'Downloading...'
        $dl = $downloader.Download()

        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $batch
        Write-Verbose 'Installing...'
        $res = $installer.Install()

        # OperationResultCode: 2 = Succeeded, 3 = SucceededWithErrors, 4 = Failed, 5 = Aborted
        $codes = @{ 0 = 'NotStarted'; 1 = 'InProgress'; 2 = 'Succeeded'; 3 = 'SucceededWithErrors'; 4 = 'Failed'; 5 = 'Aborted' }
        Write-Host ("Download: {0}; Install: {1}; Reboot required: {2}" -f $codes[[int]$dl.ResultCode], $codes[[int]$res.ResultCode], $res.RebootRequired)
        if ([int]$res.ResultCode -ge 4) { exit 1 }
    }
}
