<#
.SYNOPSIS
    Intune remediation detection: system drive is low on free space.

.DESCRIPTION
    Exit 1 (issue found, run remediation) when the system drive has less than -MinFreePercent
    or less than -MinFreeGB free. Exit 0 otherwise. Prints one summary line for the Intune report.

.PARAMETER MinFreePercent
    Minimum free space as a percentage of the drive. Default 10.

.PARAMETER MinFreeGB
    Minimum free space in GB. Default 10.

.EXAMPLE
    .\Detect.ps1 -MinFreePercent 15
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 99)][int]$MinFreePercent = 10,
    [ValidateRange(1, 10000)][int]$MinFreeGB = 10
)

try {
    $drive = $env:SystemDrive
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction Stop
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
    $freePct = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)

    if ($freePct -lt $MinFreePercent -or $freeGB -lt $MinFreeGB) {
        Write-Output "Low disk space: $drive $freeGB GB free ($freePct%), minimum $MinFreeGB GB / $MinFreePercent%"
        exit 1
    }
    Write-Output "OK: $drive $freeGB GB free ($freePct%)"
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
