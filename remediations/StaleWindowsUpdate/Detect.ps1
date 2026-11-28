<#
.SYNOPSIS
    Intune remediation detection: Windows Update has not installed anything successfully for too long,
    or its services are disabled.

.DESCRIPTION
    Reads the Windows Update Agent history and finds the most recent successful install.
    Exit 1 when that is older than -MaxAgeDays (default 35: one monthly cycle plus slack),
    when there is no successful install in the history, or when wuauserv/BITS are disabled.
#>
[CmdletBinding()]
param([ValidateRange(7, 365)][int]$MaxAgeDays = 35)

try {
    $disabled = @(Get-Service -Name wuauserv, BITS -ErrorAction Stop | Where-Object StartType -eq 'Disabled')
    if ($disabled) {
        Write-Output "Disabled service(s): $(($disabled.Name) -join ', ')"
        exit 1
    }

    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $count = $searcher.GetTotalHistoryCount()
    # Operation 1 = Installation; ResultCode 2 = Succeeded, 3 = SucceededWithErrors
    $last = @($searcher.QueryHistory(0, [math]::Max($count, 1))) |
        Where-Object { $_.Operation -eq 1 -and $_.ResultCode -in 2, 3 } |
        Sort-Object Date -Descending | Select-Object -First 1

    if (-not $last) {
        Write-Output 'No successful update installation in Windows Update history'
        exit 1
    }
    $age = [math]::Floor(((Get-Date) - $last.Date).TotalDays)
    if ($age -gt $MaxAgeDays) {
        Write-Output "Last successful update $age day(s) ago (limit $MaxAgeDays): $($last.Title)"
        exit 1
    }
    Write-Output "OK: last successful update $age day(s) ago"
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
