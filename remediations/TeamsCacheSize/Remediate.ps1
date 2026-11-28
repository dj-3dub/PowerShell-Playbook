<#
.SYNOPSIS
    Intune remediation: clear the new Teams cache, but only while Teams is closed.

.DESCRIPTION
    Runs in the signed-in user's context. If ms-teams.exe is running the script does nothing and exits 1,
    so Intune retries on the next schedule instead of closing Teams in the middle of a call.
    Otherwise it empties the cache folder; Teams rebuilds it on next launch (the user signs in again).
#>
[CmdletBinding()]
param()

try {
    $cache = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
    if (Get-Process -Name 'ms-teams' -ErrorAction SilentlyContinue) {
        Write-Output 'Teams is running; cache not cleared (will retry on next run)'
        exit 1
    }
    if (-not (Test-Path -LiteralPath $cache)) {
        Write-Output 'Nothing to do: new Teams cache not present'
        exit 0
    }

    $before = (Get-ChildItem -LiteralPath $cache -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Get-ChildItem -LiteralPath $cache -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $left = @(Get-ChildItem -LiteralPath $cache -Recurse -Force -File -ErrorAction SilentlyContinue)

    if ($left.Count) {
        Write-Output "Partially cleared: $($left.Count) file(s) in use"
        exit 1
    }
    Write-Output ("Cleared Teams cache ({0} MB)" -f [math]::Round([double]$before / 1MB))
    exit 0
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
