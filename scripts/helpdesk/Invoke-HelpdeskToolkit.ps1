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
     18.  Identity: Reset AD password
      Q.  Quit

.NOTES
    Every fix run is recorded as one JSON line in out/HelpdeskLogs/toolkit-runs.jsonl (fix, ticket,
    technician, duration, outcome). Get-ToolkitUsageReport turns that into success rates and time saved.

.PARAMETER RunLogPath
    Where to write run records. Default: <repo>/out/HelpdeskLogs/toolkit-runs.jsonl.

.EXAMPLE
    .\Invoke-HelpdeskToolkit.ps1
#>

[CmdletBinding()]
param(
    # JSON Lines file that receives one record per fix run (read by Get-ToolkitUsageReport).
    [string]$RunLogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve the folder that contains the helpdesk scripts
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$repoRoot  = Split-Path -Path (Split-Path -Path $scriptDir -Parent) -Parent
if (-not $RunLogPath) {
    $RunLogPath = Join-Path (Join-Path (Join-Path $repoRoot 'out') 'HelpdeskLogs') 'toolkit-runs.jsonl'
}
$script:SessionTicket = $null
$script:TicketAsked   = $false
$script:RunCancelled  = $false

function Get-TicketId {
    # Asked once per session (at start-up); every fix and run record reuses it.
    if (-not $script:TicketAsked) {
        $script:SessionTicket = ([string](Read-Host 'Ticket ID for this session (optional, Enter to skip)')).Trim()
        $script:TicketAsked = $true
    }
    $script:SessionTicket
}

function Write-RunRecord {
    param([System.Collections.IDictionary]$Record)
    $dir = Split-Path -Path $RunLogPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ([pscustomobject]$Record | ConvertTo-Json -Compress) | Add-Content -Path $RunLogPath -Encoding UTF8
}

function Invoke-TrackedAction {
    <#
        Runs one menu action and appends a run record: what ran, for which ticket, by whom, how long it took,
        and whether it succeeded (no exception and a zero exit code), failed, or was cancelled by the technician.
    #>
    param([string]$Key, [string]$Label, [scriptblock]$Action)
    $script:RunCancelled = $false
    $global:LASTEXITCODE = 0
    $errorText = $null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { & $Action }
    catch { $errorText = $_.Exception.Message; Write-Host "Failed: $errorText" -ForegroundColor Red }
    $sw.Stop()

    $outcome = if ($errorText -or $LASTEXITCODE -ne 0) { 'Failed' } elseif ($script:RunCancelled) { 'Cancelled' } else { 'Success' }
    try {
        Write-RunRecord ([ordered]@{
            Timestamp       = (Get-Date).ToString('o')
            Fix             = $Key
            Label           = $Label
            TicketId        = $script:SessionTicket
            Computer        = [Environment]::MachineName
            Operator        = [Environment]::UserName
            DurationSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            Outcome         = $outcome
            ExitCode        = $LASTEXITCODE
            Error           = $errorText
        })
    }
    catch { Write-Warning "Could not write run record: $($_.Exception.Message)" }
}

function Invoke-ResetPrinter {
    $script = Join-Path $scriptDir 'Reset-PrinterSubsystem.ps1'
    if (-not (Test-Path $script)) { throw "Missing script: $script" }
    & $script -Verbose
}

function Invoke-ResetTeams {
    $script = Join-Path $scriptDir 'Reset-TeamsCache.ps1'
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

    $restart = Read-Host "Restart Teams after clearing cache? (Y/N)"
    $restartSwitch = ($restart -match '^[Yy]')

    if ($restartSwitch) { & $script -Restart -Verbose }
    else { & $script -Verbose }
}

function Invoke-ResetOutlook {
    $script = Join-Path $scriptDir 'Reset-OutlookProfile.ps1'
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

    $confirm = Read-Host "This will reset the Outlook profile. Continue? (Y/N)"
    if ($confirm -notmatch '^[Yy]') { Write-Host "Cancelled." -ForegroundColor Yellow; $script:RunCancelled = $true; return }

    & $script -Verbose
}

function Invoke-RepairNetwork {
    $script = Join-Path $scriptDir 'Repair-NetworkStack.ps1'
    if (-not (Test-Path $script)) { throw "Missing script: $script" }
    & $script -Verbose
}

function Invoke-RepairWindowsUpdate {
    $script = Join-Path $scriptDir 'Repair-WindowsUpdate.ps1'
    if (-not (Test-Path $script)) { throw "Missing script: $script" }
    & $script -Verbose
}

function Invoke-CollectHelpdeskLogs {
    $script = Join-Path $scriptDir 'Export-HelpdeskLogs.ps1'
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

    $ticket = Get-TicketId
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
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

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
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

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
        if (-not $id) { Write-Host "Cancelled." -ForegroundColor Yellow; $script:RunCancelled = $true; return }
        $params.Identity = $id
    }

    if ($export) { $params.ExportCsv = $true }

    & $script @params
}

function Invoke-OneDriveRepair {
    $script = Join-Path $scriptDir 'Repair-OneDriveSync.ps1'
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

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
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

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
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

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
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

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
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

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
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

    $ticket = Get-TicketId
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
    if ([string]::IsNullOrWhiteSpace($idx)) { Write-Host "Cancelled." -ForegroundColor Yellow; $script:RunCancelled = $true; return }
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
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

    $user = Read-Host "Enter username or UPN (default current user)"
    if (-not $user) { $user = $env:USERNAME }
    $ticket = Get-TicketId

    $params = @{ Identity = $user; Verbose = $true }
    if ($ticket) { $params.TicketId = $ticket }

    & $script @params
}

function Invoke-UnlockAdAccount {
    $script = Join-Path $scriptDir 'Unlock-UserAccount.ps1'
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

    $user = Read-Host "Enter AD username/UPN to unlock"
    if (-not $user) { Write-Host "Cancelled." -ForegroundColor Yellow; $script:RunCancelled = $true; return }
    $ticket = Get-TicketId

    $params = @{ Identity = $user; Verbose = $true }
    if ($ticket) { $params.TicketId = $ticket }

    & $script @params
}

function Invoke-ForceAdPasswordReset {
    $script = Join-Path $scriptDir 'Reset-UserPassword.ps1'
    if (-not (Test-Path $script)) { throw "Missing script: $script" }

    $user = Read-Host "Enter AD username/UPN to reset password"
    if (-not $user) { Write-Host "Cancelled." -ForegroundColor Yellow; $script:RunCancelled = $true; return }
    $ticket = Get-TicketId

    $params = @{ Identity = $user; Verbose = $true }
    if ($ticket) { $params.TicketId = $ticket }

    & $script @params
}

# One table drives both the menu and dispatch. Key is the stable name used in run records and baselines.
$menu = [ordered]@{
    '1'  = @{ Key = 'ResetPrinter';        Label = 'Reset printer subsystem';               Run = { Invoke-ResetPrinter } }
    '2'  = @{ Key = 'ResetTeams';          Label = 'Reset Microsoft Teams cache';           Run = { Invoke-ResetTeams } }
    '3'  = @{ Key = 'ResetOutlook';        Label = 'Reset Outlook profile';                 Run = { Invoke-ResetOutlook } }
    '4'  = @{ Key = 'RepairNetwork';       Label = 'Repair network stack (DNS/Winsock/IP)'; Run = { Invoke-RepairNetwork } }
    '5'  = @{ Key = 'RepairWindowsUpdate'; Label = 'Repair Windows Update components';      Run = { Invoke-RepairWindowsUpdate } }
    '6'  = @{ Key = 'CollectLogs';         Label = 'Collect helpdesk logs (ZIP)';           Run = { Invoke-CollectHelpdeskLogs } }
    '7'  = @{ Key = 'ResetBrowser';        Label = 'Reset browser profiles (Chrome/Edge)';  Run = { Invoke-ResetBrowser } }
    '8'  = @{ Key = 'MailboxCapacity';     Label = 'Check mailbox capacity & retention';    Run = { Invoke-MailboxCapacityCheck } }
    '9'  = @{ Key = 'OneDriveRepair';      Label = 'Repair OneDrive sync';                  Run = { Invoke-OneDriveRepair } }
    '10' = @{ Key = 'VpnDiagnostics';      Label = 'VPN diagnostics';                       Run = { Invoke-VpnDiagnostics } }
    '11' = @{ Key = 'BitLockerHealth';     Label = 'BitLocker health check';                Run = { Invoke-BitLockerHealth } }
    '12' = @{ Key = 'OutlookOstRepair';    Label = 'Outlook OST repair';                    Run = { Invoke-OutlookOstRepair } }
    '13' = @{ Key = 'PreflightChecks';     Label = 'Endpoint pre-flight checks';            Run = { Invoke-PreflightChecks } }
    '14' = @{ Key = 'NetworkPerformance';  Label = 'Network performance diagnostics';       Run = { Invoke-NetworkPerformance } }
    '15' = @{ Key = $null;                 Label = 'View network performance logs';         Run = { Invoke-ViewNetworkPerformanceLogs } }
    '16' = @{ Key = 'SignInHealth';        Label = 'Identity: Sign-in health triage';       Run = { Invoke-IdentitySignInHealth } }
    '17' = @{ Key = 'UnlockAccount';       Label = 'Identity: Unlock AD account';           Run = { Invoke-UnlockAdAccount } }
    '18' = @{ Key = 'PasswordReset';       Label = 'Identity: Reset AD password';           Run = { Invoke-ForceAdPasswordReset } }
}

function Show-Menu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   Helpdesk Automation Toolkit (PowerShell)"
    Write-Host "==========================================" -ForegroundColor Cyan
    if ($script:SessionTicket) { Write-Host "   Ticket: $script:SessionTicket" -ForegroundColor DarkGray }
    Write-Host ""
    foreach ($k in $menu.Keys) { Write-Host ("{0,2})  {1}" -f $k, $menu[$k].Label) }
    Write-Host " Q)  Quit"
    Write-Host ""
}

$null = Get-TicketId

do {
    Show-Menu
    $choice = (Read-Host "Select an option").Trim().ToUpper()

    if ($choice -eq 'Q') {
        Write-Host "Exiting Helpdesk Toolkit." -ForegroundColor Green
    }
    elseif ($menu.Contains($choice)) {
        $item = $menu[$choice]
        if ($item.Key) { Invoke-TrackedAction -Key $item.Key -Label $item.Label -Action $item.Run }
        else { & $item.Run }
        Pause
    }
    else {
        Write-Host "Invalid selection. Choose 1-$($menu.Count) or Q." -ForegroundColor Yellow
        Pause
    }
} while ($choice -ne 'Q')
