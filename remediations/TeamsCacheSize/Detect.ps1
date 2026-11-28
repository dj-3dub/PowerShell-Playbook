<#
.SYNOPSIS
    Intune remediation detection: the new Teams cache has grown past a size limit.

.DESCRIPTION
    Runs in the signed-in user's context. Measures
    %LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams and exits 1 when it is larger
    than -MaxCacheMB. A bloated cache is a common cause of slow start-up, blank panes and sign-in loops.

.PARAMETER MaxCacheMB
    Size limit in MB. Default 1024.
#>
[CmdletBinding()]
param([ValidateRange(50, 102400)][int]$MaxCacheMB = 1024)

try {
    $cache = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
    if (-not (Test-Path -LiteralPath $cache)) {
        Write-Output 'OK: new Teams cache not present'
        exit 0
    }
    $bytes = (Get-ChildItem -LiteralPath $cache -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    $mb = [math]::Round([double]$bytes / 1MB)
    if ($mb -gt $MaxCacheMB) {
        Write-Output "Teams cache is $mb MB (limit $MaxCacheMB MB)"
        exit 1
    }
    Write-Output "OK: Teams cache is $mb MB"
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
