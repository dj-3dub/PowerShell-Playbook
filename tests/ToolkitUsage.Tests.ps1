# Helpdesk Toolkit run tracking (menu -> JSON Lines) and Get-ToolkitUsageReport aggregation.

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $root 'src/PowerShellPlaybook.psd1') -Force -ErrorAction Stop -WarningAction SilentlyContinue
    Push-Location $TestDrive

    function New-RunLog([object[]]$Records) {
        $path = Join-Path $TestDrive "runs-$(New-Guid).jsonl"
        $lines = foreach ($r in $Records) { [pscustomobject]$r | ConvertTo-Json -Compress }
        Set-Content -Path $path -Value $lines -Encoding UTF8
        $path
    }
    function New-Run([string]$Fix, [string]$Outcome, [double]$Seconds = 60, [int]$DaysAgo = 1, [string]$Ticket = 'INC1') {
        @{ Timestamp = (Get-Date).AddDays(-$DaysAgo).ToString('o'); Fix = $Fix; Label = $Fix; TicketId = $Ticket
           Computer = 'WS-1'; Operator = 'tech01'; DurationSeconds = $Seconds; Outcome = $Outcome; ExitCode = 0; Error = $null }
    }
}

AfterAll {
    Pop-Location
    Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
}

Describe 'Get-ToolkitUsageReport' {
    It 'computes success rate (excluding cancelled), time saved and status per fix' {
        $log = New-RunLog @(
            (New-Run ResetTeams Success 60); (New-Run ResetTeams Success 60); (New-Run ResetTeams Success 60)
            (New-Run ResetTeams Failed 60);  (New-Run ResetTeams Cancelled 60)
        )
        $r = Get-ToolkitUsageReport -Path $log -OutputPath (Join-Path $TestDrive 'r1')
        $row = $r.Rows | Where-Object Fix -eq 'ResetTeams'

        $row.Runs        | Should -Be 5
        $row.Succeeded   | Should -Be 3
        $row.Cancelled   | Should -Be 1
        $row.SuccessRate | Should -Be 75      # 3 of 4 attempts; the cancelled run is not an attempt
        $row.Status      | Should -Be 'Warn'
        # Baseline for ResetTeams is 20 min; each success took 1 min, so 3 x 19 = 57 minutes saved.
        $row.MinutesSaved | Should -Be 57
        $r.Html | Should -Exist
        $r.Csv  | Should -Exist
    }

    It 'grades fixes: OK at 90%+, Fail below 75%' {
        $good = 1..9 | ForEach-Object { New-Run UnlockAccount Success }
        $bad = @((New-Run PreflightChecks Success), (New-Run PreflightChecks Failed), (New-Run PreflightChecks Failed))
        $r = Get-ToolkitUsageReport -Path (New-RunLog (@($good) + (New-Run UnlockAccount Failed) + $bad)) -OutputPath (Join-Path $TestDrive 'r2')
        ($r.Rows | Where-Object Fix -eq 'UnlockAccount').Status   | Should -Be 'OK'
        ($r.Rows | Where-Object Fix -eq 'PreflightChecks').Status | Should -Be 'Fail'
    }

    It 'counts no time saved for fixes without a baseline' {
        $r = Get-ToolkitUsageReport -Path (New-RunLog @((New-Run SomethingNew Success))) -OutputPath (Join-Path $TestDrive 'r3')
        $r.Rows[0].ManualMinutes | Should -BeNullOrEmpty
        $r.Rows[0].MinutesSaved  | Should -Be 0
    }

    It 'honours -Since and computes totals' {
        $log = New-RunLog @(
            (New-Run ResetPrinter Success 30 -DaysAgo 40 -Ticket 'INC9')
            (New-Run ResetPrinter Success 30 -DaysAgo 2 -Ticket 'INC1')
            (New-Run PasswordReset Success 30 -DaysAgo 1 -Ticket 'INC2')
        )
        $r = Get-ToolkitUsageReport -Path $log -Since (Get-Date).AddDays(-7) -OutputPath (Join-Path $TestDrive 'r4')
        $r.Totals.Runs        | Should -Be 2
        $r.Totals.Tickets     | Should -Be 2
        $r.Totals.SuccessRate | Should -Be 100
    }

    It 'skips malformed lines instead of failing' {
        $log = New-RunLog @((New-Run ResetTeams Success))
        Add-Content -Path $log -Value '{not json'
        (Get-ToolkitUsageReport -Path $log -OutputPath (Join-Path $TestDrive 'r5')).Totals.Runs | Should -Be 1
    }

    It 'throws with guidance when the log does not exist' {
        { Get-ToolkitUsageReport -Path (Join-Path $TestDrive 'missing.jsonl') } | Should -Throw -ExpectedMessage '*Invoke-HelpdeskToolkit*'
    }

    It '-Mock is deterministic and labelled as sample data' {
        $a = Get-ToolkitUsageReport -Mock -OutputPath (Join-Path $TestDrive 'm1')
        $b = Get-ToolkitUsageReport -Mock -OutputPath (Join-Path $TestDrive 'm2')
        $a.Totals.Runs | Should -BeGreaterThan 50
        $a.Totals.HoursSaved | Should -Be $b.Totals.HoursSaved
        Get-Content $a.Html -Raw | Should -Match '\(sample data\)'
        # Same numbers in a separate process too (guards against hashtable ordering).
        $other = pwsh -NoProfile -Command "Import-Module '$(Join-Path $root 'src/PowerShellPlaybook.psd1')' -WarningAction SilentlyContinue; (Get-ToolkitUsageReport -Mock -OutputPath '$(Join-Path $TestDrive 'm3')').Totals.HoursSaved"
        [double]($other | Select-Object -Last 1) | Should -Be $a.Totals.HoursSaved
    }
}

Describe 'Invoke-HelpdeskToolkit run tracking' {
    BeforeAll {
        $menuScript = Join-Path $root 'scripts/helpdesk/Invoke-HelpdeskToolkit.ps1'
        $state = @{ Answers = [System.Collections.Queue]::new() }
        function Invoke-Menu([string[]]$Answers, [string]$Script = $menuScript) {
            $state.Answers.Clear()
            foreach ($a in $Answers) { $state.Answers.Enqueue($a) }
            $log = Join-Path $TestDrive "menu-$(New-Guid).jsonl"
            & $Script -RunLogPath $log *> $null
            if (Test-Path $log) { @(Get-Content $log | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() }
        }
    }

    BeforeEach {
        Mock Read-Host { if ($state.Answers.Count) { $state.Answers.Dequeue() } else { 'Q' } }
        Mock Pause { }
        Mock Clear-Host { }
    }

    It 'records a failed fix with its error and the session ticket' {
        # Ticket is asked once at start-up; 16 = sign-in triage, which fails because its script is missing.
        # A copy of the menu with no fix scripts next to it: every fix fails the same way on any OS.
        $isolated = Join-Path $TestDrive 'isolated/scripts/helpdesk'
        New-Item -ItemType Directory -Path $isolated -Force | Out-Null
        Copy-Item $menuScript $isolated
        $records = Invoke-Menu 'INC0042', '16', 'Q' -Script (Join-Path $isolated 'Invoke-HelpdeskToolkit.ps1')
        $records.Count       | Should -Be 1
        $records[0].Fix      | Should -Be 'SignInHealth'
        $records[0].Outcome  | Should -Be 'Failed'
        $records[0].Error    | Should -Match 'Missing script'
        $records[0].TicketId | Should -Be 'INC0042'
    }

    It 'records a cancelled fix as Cancelled' {
        $records = Invoke-Menu '', '17', '', 'Q'      # no ticket; Unlock account; Enter at the username prompt
        $records[0].Fix     | Should -Be 'UnlockAccount'
        $records[0].Outcome | Should -Be 'Cancelled'
    }

    It 'does not record viewing logs' {
        $records = Invoke-Menu '', '15', '', 'Q'
        $records | Should -BeNullOrEmpty
    }
}
