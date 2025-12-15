<#
.SYNOPSIS
    Interactive Helpdesk Automation Toolkit launcher.

.DESCRIPTION
    Provides a simple menu to run common helpdesk automations:
      1.  Reset printer subsystem
      2.  Reset Microsoft Teams cache
      3.  Reset Outlook profile
      4.  Repair network stack (DNS/Winsock/IP)
      5.  Repair Windows Update components
      6.  Collect helpdesk logs (ZIP)
      7.  Reset browser profiles (Chrome/Edge)
      8.  Check mailbox capacity & retention (Exchange)
      9.  Repair OneDrive sync (Soft/Reset + logs)
     10.  VPN diagnostics (connectivity + routing)
     11.  BitLocker health check (local machine)
     12.  Outlook OST repair (scan/rebuild)
     13.  Endpoint pre-flight checks (OS/disk/memory/network/events)
     14.  Network performance diagnostics (slow/intermittent)
     15.  View Network Performance Logs
     16.  Identity: Sign-in health triage
     17.  Identity: Unlock AD account
     18.  Identity: Force AD password reset
      Q.  Quit

.EXAMPLE
    .\Invoke-HelpdeskToolkit.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve the folder that contains the helpdesk scripts
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

function Invoke-ResetPrinter {
    $script = Join-Path $scriptDir 'Reset-PrinterSubsystem.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }
    & $script -Verbose
}

function Invoke-ResetTeams {
    $script = Join-Path $scriptDir 'Reset-TeamsCache.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $restart = Read-Host "Restart Teams after clearing cache? (Y/N)"
    $restartSwitch = ($restart -match '^[Yy]')

    if ($restartSwitch) { & $script -Restart -Verbose }
    else { & $script -Verbose }
}

function Invoke-ResetOutlook {
    $script = Join-Path $scriptDir 'Reset-OutlookProfile.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $confirm = Read-Host "This will reset the Outlook profile. Continue? (Y/N)"
    if ($confirm -notmatch '^[Yy]') { Write-Host "Cancelled." -ForegroundColor Yellow; return }

    & $script -Verbose
}

function Invoke-RepairNetwork {
    $script = Join-Path $scriptDir 'Repair-NetworkStack.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }
    & $script -Verbose
}

function Invoke-RepairWindowsUpdate {
    $script = Join-Path $scriptDir 'Repair-WindowsUpdate.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }
    & $script -Verbose
}

function Invoke-CollectHelpdeskLogs {
    $script = Join-Path $scriptDir 'Collect-HelpdeskLogs.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $ticket = Read-Host "Enter Ticket ID (optional)"
    $hoursInput = Read-Host "Hours of event logs to collect? (default 24)"
    $hours = if ($hoursInput -match '^\d+$') { [int]$hoursInput } else { 24 }

    if ([string]::IsNullOrWhiteSpace($ticket)) {
        & $script -Hours $hours -Verbose
    }
    else {
        & $script -TicketId $ticket -Hours $hours -Verbose
    }
}

function Invoke-ResetBrowser {
    $script = Join-Path $scriptDir 'Reset-BrowserProfile.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $browser = Read-Host "Browser (Chrome/Edge/All, default All)"
    if (-not $browser) { $browser = "All" }

    $mode = Read-Host "Mode? (C = cache only, R = full reset)"
    $clearCacheOnly = -not ($mode -match '^[Rr]')

    $backup = -not ((Read-Host "Backup first? (Y/N, default Y)") -match '^[Nn]')
    $restart = ((Read-Host "Restart browser after reset? (Y/N)") -match '^[Yy]')

    $params = @{
        Browser = $browser
        Verbose = $true
    }
    if ($clearCacheOnly) { $params.ClearCacheOnly = $true }
    if ($backup)         { $params.Backup = $true }
    if ($restart)        { $params.Restart = $true }

    & $script @params
}

function Invoke-MailboxCapacityCheck {
    $script = Join-Path $scriptDir 'Test-MailboxCapacityAndRetention.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    Write-Host "NOTE: Must be connected to Exchange Online first." -ForegroundColor Yellow

    $scope = Read-Host "Single mailbox (S) or All (A)? (default S)"
    if (-not $scope) { $scope = 'S' }

    $thresholdInput = Read-Host "Threshold percent for NearCapacity flag (default 90)"
    $threshold = if ($thresholdInput -match '^\d+$') { [int]$thresholdInput } else { 90 }

    $export = -not ((Read-Host "Export CSV? (Y/N, default Y)") -match '^[Nn]')

    $params = @{
        WarningThresholdPercent = $threshold
        Verbose                 = $true
    }

    if ($scope -match '^[Aa]') {
        $params.AllMailboxes = $true
    }
    else {
        $id = Read-Host "Enter mailbox identity"
        if (-not $id) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
        $params.Identity = $id
    }

    if ($export) { $params.ExportCsv = $true }

    & $script @params
}

function Invoke-OneDriveRepair {
    $script = Join-Path $scriptDir 'Repair-OneDriveSync.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $mode = Read-Host "Mode: Soft or Reset (S/R, default R)"
    $mode = if ($mode -match '^[Ss]') { 'Soft' } else { 'Reset' }

    $backup = -not ((Read-Host "Backup logs? (Y/N, default Y)") -match '^[Nn]')
    $restart = -not ((Read-Host "Restart OneDrive? (Y/N, default Y)") -match '^[Nn]')

    $params = @{
        Mode    = $mode
        Verbose = $true
    }
    if ($backup)  { $params.BackupLogs = $true }
    if ($restart) { $params.Restart = $true }

    & $script @params
}

function Invoke-VpnDiagnostics {
    $script = Join-Path $scriptDir 'Test-VpnDiagnostics.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $vpnName  = Read-Host "VPN name (optional)"
    $internal = Read-Host "Internal test host (optional)"
    $public   = Read-Host "Public test host (default 8.8.8.8)"
    if (-not $public) { $public = "8.8.8.8" }

    $logs = -not ((Read-Host "Collect logs? (Y/N, default Y)") -match '^[Nn]')

    $params = @{
        PublicTestHost = $public
        Verbose        = $true
    }
    if ($vpnName)  { $params.VpnName = $vpnName }
    if ($internal) { $params.InternalTestHost = $internal }
    if ($logs)     { $params.CollectLogs = $true }

    & $script @params
}

function Invoke-BitLockerHealth {
    $script = Join-Path $scriptDir 'Test-BitLockerHealth.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $export = -not ((Read-Host "Export CSV? (Y/N, default Y)") -match '^[Nn]')
    $include = ((Read-Host "Include Recovery Keys? (Sensitive!) (Y/N)") -match '^[Yy]')

    $params = @{
        Verbose = $true
    }
    if ($export)  { $params.ExportCsv = $true }
    if ($include) { $params.IncludeRecoveryKeys = $true }

    & $script @params
}

function Invoke-OutlookOstRepair {
    $script = Join-Path $scriptDir 'Repair-OutlookOst.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $identity = Read-Host "Filter OSTs by identity (optional)"
    $modeInput = Read-Host "Mode: Rebuild (R), Scan (S), Both (B)"
    $mode = switch -Regex ($modeInput) {
        '^[Ss]' { 'Scan' }
        '^[Bb]' { 'Both' }
        default { 'Rebuild' }
    }

    $backup = -not ((Read-Host "Backup OST first? (Y/N, default Y)") -match '^[Nn]')

    $params = @{
        Mode    = $mode
        Verbose = $true
    }
    if ($identity) { $params.Identity = $identity }
    if ($backup)   { $params.Backup = $true }

    & $script @params
}

function Invoke-PreflightChecks {
    $script = Join-Path $scriptDir 'Test-EndpointPreflight.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $hoursInput = Read-Host "Hours of event logs (default 4)"
    $hours = if ($hoursInput -match '^\d+$') { [int]$hoursInput } else { 4 }

    $testHost = Read-Host "Connectivity test host (optional)"
    $logs = -not ((Read-Host "Collect logs? (Y/N, default Y)") -match '^[Nn]')

    $params = @{
        HoursForEvents = $hours
        Verbose        = $true
    }
    if ($testHost) { $params.TestHost = $testHost }
    if ($logs)     { $params.CollectLogs = $true }

    & $script @params
}

function Invoke-NetworkPerformance {
    $script = Join-Path $scriptDir 'Test-NetworkPerformance.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $ticket = Read-Host "Ticket ID (optional)"
    $remed  = Read-Host "Run safe remediation (DNS flush) if suggested? (Y/N, default N)"

    $params = @{ Verbose = $true }
    if ($ticket) { $params.TicketId = $ticket }
    if ($remed -match '^[Yy]') { $params.EnableSafeRemediation = $true }

    & $script @params
}

function Invoke-ViewNetworkPerformanceLogs {
    $logsDir = Join-Path $scriptDir '..\..\out\HelpdeskLogs'
    try { $logsDir = (Resolve-Path $logsDir).Path } catch { $logsDir = $null }

    if (-not $logsDir -or -not (Test-Path $logsDir)) {
        Write-Host "Log directory not found: out/HelpdeskLogs" -ForegroundColor Yellow
        return
    }

    $logs = Get-ChildItem -Path $logsDir -Filter 'NetPerf_*.txt' -File -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending

    if (-not $logs) {
        Write-Host "No NetPerf logs found." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "=== Network Performance Logs ===" -ForegroundColor Cyan
    for ($i = 0; $i -lt $logs.Count; $i++) {
        Write-Host ("[{0}] {1} ({2})" -f $i, $logs[$i].Name, $logs[$i].LastWriteTime)
    }

    $idx = Read-Host "Select log number to view (Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($idx)) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    if ($idx -notmatch '^\d+$') { Write-Host "Invalid selection." -ForegroundColor Yellow; return }
    $n = [int]$idx
    if ($n -lt 0 -or $n -ge $logs.Count) { Write-Host "Invalid selection." -ForegroundColor Yellow; return }

    Write-Host ""
    Write-Host ("=== Viewing {0} ===" -f $logs[$n].FullName) -ForegroundColor Green
    Write-Host ""
    Get-Content -Path $logs[$n].FullName | Out-Host
    Write-Host ""
    Write-Host "=== End ===" -ForegroundColor Green
}

function Invoke-IdentitySignInHealth {
    $script = Join-Path $scriptDir 'Test-UserSignInHealth.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $user = Read-Host "Enter username or UPN (default current user)"
    if (-not $user) { $user = $env:USERNAME }
    $ticket = Read-Host "Ticket ID (optional)"

    $params = @{ Identity = $user; Verbose = $true }
    if ($ticket) { $params.TicketId = $ticket }

    & $script @params
}

function Invoke-UnlockAdAccount {
    $script = Join-Path $scriptDir 'Unlock-UserAccount.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $user = Read-Host "Enter AD username/UPN to unlock"
    if (-not $user) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    $ticket = Read-Host "Ticket ID (optional)"

    $params = @{ Identity = $user; Verbose = $true }
    if ($ticket) { $params.TicketId = $ticket }

    & $script @params
}

function Invoke-ForceAdPasswordReset {
    $script = Join-Path $scriptDir 'Force-PasswordReset.ps1'
    if (-not (Test-Path $script)) { Write-Warning "Missing: $script"; return }

    $user = Read-Host "Enter AD username/UPN to reset password"
    if (-not $user) { Write-Host "Cancelled." -ForegroundColor Yellow; return }
    $ticket = Read-Host "Ticket ID (optional)"

    $params = @{ Identity = $user; Verbose = $true }
    if ($ticket) { $params.TicketId = $ticket }

    & $script @params
}

function Show-Menu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   Helpdesk Automation Toolkit (PowerShell)"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " 1)  Reset printer subsystem"
    Write-Host " 2)  Reset Microsoft Teams cache"
    Write-Host " 3)  Reset Outlook profile"
    Write-Host " 4)  Repair network stack (DNS/Winsock/IP)"
    Write-Host " 5)  Repair Windows Update components"
    Write-Host " 6)  Collect helpdesk logs (ZIP)"
    Write-Host " 7)  Reset browser profiles (Chrome/Edge)"
    Write-Host " 8)  Check mailbox capacity & retention"
    Write-Host " 9)  Repair OneDrive sync"
    Write-Host "10)  VPN diagnostics"
    Write-Host "11)  BitLocker health check"
    Write-Host "12)  Outlook OST repair"
    Write-Host "13)  Endpoint pre-flight checks"
    Write-Host "14)  Network performance diagnostics"
    Write-Host "15)  View Network Performance Logs"
    Write-Host "16)  Identity: Sign-in health triage"
    Write-Host "17)  Identity: Unlock AD account"
    Write-Host "18)  Identity: Force AD password reset"
    Write-Host " Q)  Quit"
    Write-Host ""
}

do {
    Show-Menu
    $choice = Read-Host "Select an option"

    switch ($choice.ToUpper()) {
        '1'  { Invoke-ResetPrinter                ; Pause }
        '2'  { Invoke-ResetTeams                  ; Pause }
        '3'  { Invoke-ResetOutlook                ; Pause }
        '4'  { Invoke-RepairNetwork               ; Pause }
        '5'  { Invoke-RepairWindowsUpdate         ; Pause }
        '6'  { Invoke-CollectHelpdeskLogs         ; Pause }
        '7'  { Invoke-ResetBrowser                ; Pause }
        '8'  { Invoke-MailboxCapacityCheck        ; Pause }
        '9'  { Invoke-OneDriveRepair              ; Pause }
        '10' { Invoke-VpnDiagnostics              ; Pause }
        '11' { Invoke-BitLockerHealth             ; Pause }
        '12' { Invoke-OutlookOstRepair            ; Pause }
        '13' { Invoke-PreflightChecks             ; Pause }
        '14' { Invoke-NetworkPerformance          ; Pause }
        '15' { Invoke-ViewNetworkPerformanceLogs  ; Pause }
        '16' { Invoke-IdentitySignInHealth        ; Pause }
        '17' { Invoke-UnlockAdAccount             ; Pause }
        '18' { Invoke-ForceAdPasswordReset        ; Pause }
        'Q'  { Write-Host "Exiting Helpdesk Toolkit." -ForegroundColor Green }
        default {
            Write-Host "Invalid selection. Choose 1-18 or Q." -ForegroundColor Yellow
            Pause
        }
    }

} while ($choice.ToUpper() -ne 'Q')
