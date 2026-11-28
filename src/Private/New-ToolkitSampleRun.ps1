function New-ToolkitSampleRun {
    <#
        Deterministic sample Helpdesk Toolkit run records for demos and tests (fixed seed, so the same
        numbers every time). Shaped like the real log: fix key, ticket, technician, duration, outcome.
    #>
    [CmdletBinding()]
    param(
        [int]$Days = 30,
        [string[]]$Keys,
        [int]$Seed = 42
    )
    $rng = New-Object System.Random $Seed
    # Relative frequency, typical duration (s) and success rate per fix; the rest get a default profile.
    $fixProfile = @{
        ResetTeams          = @(14, 70, 0.97);  ResetPrinter       = @(9, 55, 0.95);  PasswordReset      = @(12, 40, 0.99)
        UnlockAccount       = @(11, 25, 0.99);  RepairNetwork      = @(7, 95, 0.92);  ResetOutlook       = @(6, 150, 0.90)
        OneDriveRepair      = @(5, 180, 0.88);  RepairWindowsUpdate = @(4, 600, 0.80); OutlookOstRepair   = @(3, 420, 0.72)
        CollectLogs         = @(6, 120, 0.98);  VpnDiagnostics     = @(4, 90, 0.95);  SignInHealth       = @(5, 35, 0.98)
    }
    $labels = @{
        ResetPrinter = 'Reset printer subsystem'; ResetTeams = 'Reset Microsoft Teams cache'; ResetOutlook = 'Reset Outlook profile'
        RepairNetwork = 'Repair network stack (DNS/Winsock/IP)'; RepairWindowsUpdate = 'Repair Windows Update components'
        CollectLogs = 'Collect helpdesk logs (ZIP)'; ResetBrowser = 'Reset browser profiles (Chrome/Edge)'
        MailboxCapacity = 'Check mailbox capacity & retention'; OneDriveRepair = 'Repair OneDrive sync'; VpnDiagnostics = 'VPN diagnostics'
        BitLockerHealth = 'BitLocker health check'; OutlookOstRepair = 'Outlook OST repair'; PreflightChecks = 'Endpoint pre-flight checks'
        NetworkPerformance = 'Network performance diagnostics'; SignInHealth = 'Identity: Sign-in health triage'
        UnlockAccount = 'Identity: Unlock AD account'; PasswordReset = 'Identity: Reset AD password'
    }
    $weighted = foreach ($k in $Keys) {
        $p = if ($fixProfile.ContainsKey($k)) { $fixProfile[$k] } else { @(2, 60, 0.95) }
        for ($i = 0; $i -lt $p[0]; $i++) { [pscustomobject]@{ Key = $k; Seconds = $p[1]; Rate = $p[2] } }
    }
    $weighted = @($weighted)
    if (-not $weighted) { return @() }

    $start = (Get-Date).Date.AddDays(-$Days + 1)
    $techs = 'tech01', 'tech02', 'tech03', 'tech04'
    $ticket = 104200
    foreach ($day in 0..($Days - 1)) {
        $date = $start.AddDays($day)
        if ($date.DayOfWeek -in 'Saturday', 'Sunday') { continue }
        foreach ($n in 1..$rng.Next(3, 9)) {
            $w = $weighted[$rng.Next($weighted.Count)]
            $ticket++
            $roll = $rng.NextDouble()
            $outcome = if ($roll -lt $w.Rate) { 'Success' } elseif ($roll -lt $w.Rate + 0.03) { 'Cancelled' } else { 'Failed' }
            [pscustomobject]@{
                Timestamp       = $date.AddHours(8 + $rng.Next(0, 9)).AddMinutes($rng.Next(0, 60)).ToString('o')
                Fix             = $w.Key
                Label           = $(if ($labels.ContainsKey($w.Key)) { $labels[$w.Key] } else { $w.Key })
                TicketId        = "INC0$ticket"
                Computer        = 'WS-{0:D4}' -f $rng.Next(1, 400)
                Operator        = $techs[$rng.Next($techs.Count)]
                DurationSeconds = [math]::Round($w.Seconds * (0.6 + $rng.NextDouble() * 0.8), 1)
                Outcome         = $outcome
                ExitCode        = if ($outcome -eq 'Failed') { 1 } else { 0 }
                Error           = if ($outcome -eq 'Failed') { 'Sample failure' } else { $null }
                Source          = 'Mock'
            }
        }
    }
}
