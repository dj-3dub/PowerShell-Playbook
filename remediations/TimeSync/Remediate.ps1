<#
.SYNOPSIS
    Intune remediation: restore Windows Time synchronisation and force a resync.

.DESCRIPTION
    Runs as SYSTEM.
      1. Sets W32Time to Automatic and starts it.
      2. Domain-joined: syncs from the domain hierarchy (domhier).
         Workgroup / Entra-joined with no source: uses -NtpServer (default time.windows.com).
      3. Forces a resync and re-measures the offset.
    Exit 0 when the offset is back within -MaxSkewSeconds, 1 otherwise.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 3600)][int]$MaxSkewSeconds = 60,
    [string]$NtpServer = 'time.windows.com'
)

function Get-TimeSource {
    ((w32tm /query /source) | Out-String).Trim() -replace ',0x[0-9a-fA-F]+$', ''
}

function Get-TimeOffsetSeconds([string]$Source) {
    $out = w32tm /stripchart /computer:$Source /samples:1 /dataonly 2>&1 | Out-String
    if ($out -match '([+-]\d+[\.,]\d+)s') { return [double]($Matches[1] -replace ',', '.') }
    $null
}

try {
    Set-Service -Name W32Time -StartupType Automatic -ErrorAction Stop
    if ((Get-Service -Name W32Time).Status -ne 'Running') { Start-Service -Name W32Time -ErrorAction Stop }

    $domainJoined = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
    if ($domainJoined) {
        w32tm /config /syncfromflags:domhier /update | Out-Null
        $mode = 'domain hierarchy'
    }
    elseif ((Get-TimeSource) -match 'Local CMOS Clock|Free-running System Clock|^$') {
        w32tm /config /manualpeerlist:"$NtpServer,0x9" /syncfromflags:manual /update | Out-Null
        $mode = "NTP $NtpServer"
    }
    else {
        $mode = 'existing source'
    }

    w32tm /resync /force | Out-Null
    $source = Get-TimeSource
    $offset = Get-TimeOffsetSeconds $source

    if ($null -eq $offset -or [math]::Abs($offset) -gt $MaxSkewSeconds) {
        Write-Output ("Resync attempted ($mode) but offset to '{0}' is {1}" -f $source, $(if ($null -eq $offset) { 'unknown' } else { '{0:N1}s' -f $offset }))
        exit 1
    }
    Write-Output ("Time synced via {0}: {1:N2}s from {2}" -f $mode, $offset, $source)
    exit 0
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
