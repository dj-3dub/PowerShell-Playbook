function Get-ToolkitUsageReport {
    <#
    .SYNOPSIS
    Summarises Helpdesk Toolkit runs: how often each fix is used, how often it works, and the time it saves.

    .DESCRIPTION
    Reads the JSON Lines run log written by scripts/helpdesk/Invoke-HelpdeskToolkit.ps1 (one record per fix run:
    fix, ticket, technician, duration, outcome) and produces one row per fix:

      Runs, Succeeded, Failed, Cancelled, SuccessRate, AvgSeconds
      ManualMinutes   estimated hands-on time for the same fix without the toolkit (src/config/helpdesk-baselines.json)
      MinutesSaved    Succeeded x (ManualMinutes - average toolkit minutes)
      Status          OK >= 90% success, Warn >= 75%, Fail below (a fix that often fails needs attention)

    Totals (runs, tickets, technicians, overall success rate, hours saved) are included in the report header and
    in the returned object. Cancelled runs are excluded from the success rate.

    .PARAMETER Path
    Run log to read. Default ./out/HelpdeskLogs/toolkit-runs.jsonl.

    .PARAMETER Since
    Only include runs on or after this date. Default: everything in the log.

    .PARAMETER BaselinePath
    JSON file with ManualMinutes per fix key. Default: the module's config/helpdesk-baselines.json.

    .PARAMETER OutputPath
    Folder for the CSV and HTML report. Default ./reports.

    .PARAMETER Mock
    Use 30 days of generated sample runs instead of a log file (for demos); the report is titled "sample data".

    .EXAMPLE
    Get-ToolkitUsageReport -Since (Get-Date).AddDays(-30)

    .EXAMPLE
    (Get-ToolkitUsageReport -Mock).Totals

    .OUTPUTS
    PSCustomObject with Rows, Totals, Csv and Html.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = './out/HelpdeskLogs/toolkit-runs.jsonl',
        [datetime]$Since,
        [string]$BaselinePath = (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'config') 'helpdesk-baselines.json'),
        [string]$OutputPath = './reports',
        [switch]$Mock
    )

    $manual = @{}
    if (Test-Path $BaselinePath) {
        $b = Get-Content $BaselinePath -Raw | ConvertFrom-Json
        foreach ($p in $b.ManualMinutes.PSObject.Properties) { $manual[$p.Name] = [double]$p.Value }
    }
    else {
        Write-Warning "Baseline file not found ($BaselinePath); time saved will be 0."
    }

    if ($Mock) {
        # Sorted: .NET randomises hashtable key order per process, which would make the sample data vary.
        $runs = New-ToolkitSampleRun -Days 30 -Keys @($manual.Keys | Sort-Object)
    }
    else {
        if (-not (Test-Path $Path)) { throw "Run log not found: $Path. Run scripts/helpdesk/Invoke-HelpdeskToolkit.ps1 to create it." }
        $runs = foreach ($line in Get-Content -Path $Path) {
            if (-not $line.Trim()) { continue }
            try { $line | ConvertFrom-Json } catch { Write-Verbose "Skipping malformed line: $line" }
        }
    }

    $runs = @($runs | ForEach-Object {
            $_ | Add-Member -NotePropertyName When -NotePropertyValue ([datetime]$_.Timestamp) -Force -PassThru
        })
    if ($PSBoundParameters.ContainsKey('Since')) { $runs = @($runs | Where-Object { $_.When -ge $Since }) }

    $rows = foreach ($g in ($runs | Group-Object Fix)) {
        $ok = @($g.Group | Where-Object Outcome -eq 'Success')
        $failed = @($g.Group | Where-Object Outcome -eq 'Failed').Count
        $cancelled = @($g.Group | Where-Object Outcome -eq 'Cancelled').Count
        $attempts = $ok.Count + $failed
        $rate = if ($attempts) { [math]::Round(100 * $ok.Count / $attempts, 1) } else { $null }
        $avgSec = [math]::Round((($g.Group | Measure-Object DurationSeconds -Average).Average), 0)
        $manualMin = if ($manual.ContainsKey($g.Name)) { $manual[$g.Name] } else { $null }
        $saved = if ($null -ne $manualMin) { [math]::Round($ok.Count * [math]::Max([double]0, $manualMin - $avgSec / 60), 0) } else { 0 }
        $status = if ($null -eq $rate) { 'Info' } elseif ($rate -ge 90) { 'OK' } elseif ($rate -ge 75) { 'Warn' } else { 'Fail' }

        [pscustomobject]@{
            Fix           = $g.Name
            Label         = @($g.Group)[0].Label
            Runs          = $g.Count
            Succeeded     = $ok.Count
            Failed        = $failed
            Cancelled     = $cancelled
            SuccessRate   = $rate
            AvgSeconds    = $avgSec
            ManualMinutes = $manualMin
            MinutesSaved  = $saved
            Status        = $status
        }
    }
    $rows = @($rows | Sort-Object MinutesSaved, Runs -Descending)

    $okAll = @($runs | Where-Object Outcome -eq 'Success').Count
    $attemptsAll = @($runs | Where-Object Outcome -in 'Success', 'Failed').Count
    $first = ($runs | Measure-Object When -Minimum).Minimum
    $last = ($runs | Measure-Object When -Maximum).Maximum
    $totals = [pscustomobject]@{
        Period      = if ($runs) { '{0:yyyy-MM-dd} to {1:yyyy-MM-dd}' -f $first, $last } else { '' }
        Runs        = $runs.Count
        Tickets     = @($runs | Where-Object TicketId | Select-Object -ExpandProperty TicketId -Unique).Count
        Technicians = @($runs | Select-Object -ExpandProperty Operator -Unique).Count
        SuccessRate = if ($attemptsAll) { [math]::Round(100 * $okAll / $attemptsAll, 1) } else { $null }
        HoursSaved  = [math]::Round((($rows | Measure-Object MinutesSaved -Sum).Sum) / 60, 1)
    }

    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    $base = Join-Path $OutputPath ('ToolkitUsage-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmm'))
    $rows | Export-PlaybookCsv -Path "$base.csv"

    $title = 'Helpdesk Toolkit Usage'
    if ($Mock) { $title += ' (sample data)' }
    $meta = [ordered]@{
        Period          = $totals.Period
        Runs            = $totals.Runs
        Tickets         = $totals.Tickets
        Technicians     = $totals.Technicians
        'Success rate'  = "$($totals.SuccessRate)%"
        'Hours saved'   = $totals.HoursSaved
    }
    $columns = 'Label', 'Runs', 'Succeeded', 'Failed', 'Cancelled', 'SuccessRate', 'AvgSeconds', 'ManualMinutes', 'MinutesSaved', 'Status'
    [IO.File]::WriteAllText("$base.html", (ConvertTo-ReportHtml -Title $title -Data $rows -Meta $meta -Property $columns), [Text.Encoding]::UTF8)
    Write-Information "Report: $base.html"

    [pscustomobject]@{ Rows = $rows; Totals = $totals; Csv = "$base.csv"; Html = "$base.html" }
}
