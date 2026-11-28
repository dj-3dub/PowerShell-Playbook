<#
.SYNOPSIS
    Intune remediation: free space on the system drive by clearing caches that Windows rebuilds.

.DESCRIPTION
    Runs as SYSTEM. Removes files older than -OlderThanDays from:
      - %WINDIR%\Temp
      - every user profile's AppData\Local\Temp
      - %WINDIR%\SoftwareDistribution\Download (Windows Update download cache)
    and clears the Delivery Optimization cache. User documents, the Recycle Bin and Downloads are never touched.

    Exit 0 when the drive is back above the detection thresholds, 1 otherwise (so Intune shows it as
    "remediation failed" and someone looks at it). Prints one summary line.

.PARAMETER OlderThanDays
    Only delete files last written more than this many days ago. Default 7.

.PARAMETER MinFreePercent
    Same threshold as Detect.ps1. Default 10.

.PARAMETER MinFreeGB
    Same threshold as Detect.ps1. Default 10.

.PARAMETER CleanupPath
    Folders to clean. Defaults to the list above; overridable for testing.
#>
[CmdletBinding()]
param(
    [ValidateRange(0, 365)][int]$OlderThanDays = 7,
    [ValidateRange(1, 99)][int]$MinFreePercent = 10,
    [ValidateRange(1, 10000)][int]$MinFreeGB = 10,
    [string[]]$CleanupPath
)

function Get-SystemDriveFree {
    $d = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction Stop
    [pscustomobject]@{ Bytes = [double]$d.FreeSpace; Percent = [math]::Round(($d.FreeSpace / $d.Size) * 100, 1) }
}

try {
    if (-not $CleanupPath) {
        $CleanupPath = @(Join-Path $env:windir 'Temp'; Join-Path $env:windir 'SoftwareDistribution\Download')
        $profiles = Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special = FALSE' -ErrorAction SilentlyContinue
        foreach ($p in $profiles) { $CleanupPath += Join-Path $p.LocalPath 'AppData\Local\Temp' }
    }

    $before = Get-SystemDriveFree
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $removed = 0

    foreach ($path in $CleanupPath) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $removed++ } catch { Write-Verbose "In use: $($_.Exception.Message)" }
            }
        # Remove folders left empty by the cleanup (deepest first).
        Get-ChildItem -LiteralPath $path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
        Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $after = Get-SystemDriveFree
    $freedGB = [math]::Round([math]::Max([double]0, $after.Bytes - $before.Bytes) / 1GB, 2)   # [double]0: an int literal would pick Max(int,int) and overflow past 2 GB
    $afterGB = [math]::Round($after.Bytes / 1GB, 1)
    $summary = "Removed $removed file(s), freed $freedGB GB; $env:SystemDrive now $afterGB GB free ($($after.Percent)%)"

    if ($after.Percent -lt $MinFreePercent -or $afterGB -lt $MinFreeGB) {
        Write-Output "Still low after cleanup: $summary"
        exit 1
    }
    Write-Output $summary
    exit 0
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
