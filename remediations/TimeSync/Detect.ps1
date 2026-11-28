<#
.SYNOPSIS
    Intune remediation detection: Windows Time is stopped, has no real time source, or the clock has drifted.

.DESCRIPTION
    Clock skew beyond 5 minutes breaks Kerberos (domain sign-in, file shares) and causes certificate and
    MFA errors that are hard to diagnose from the helpdesk. Exit 1 when:
      - the W32Time service is not running
      - the time source is the local CMOS / free-running clock
      - the measured offset to the source exceeds -MaxSkewSeconds (default 60, well inside Kerberos' 300)
#>
[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$MaxSkewSeconds = 60)

function Get-TimeSource {
    ((w32tm /query /source) | Out-String).Trim() -replace ',0x[0-9a-fA-F]+$', ''
}

function Get-TimeOffsetSeconds([string]$Source) {
    # Sample line: "18:00:00, +00.0153462s" (decimal separator may be a comma in some locales)
    $out = w32tm /stripchart /computer:$Source /samples:1 /dataonly 2>&1 | Out-String
    if ($out -match '([+-]\d+[\.,]\d+)s') { return [double]($Matches[1] -replace ',', '.') }
    $null
}

try {
    $svc = Get-Service -Name W32Time -ErrorAction Stop
    if ($svc.Status -ne 'Running') {
        Write-Output "W32Time service is $($svc.Status)"
        exit 1
    }
    $source = Get-TimeSource
    if (-not $source -or $source -match 'Local CMOS Clock|Free-running System Clock') {
        Write-Output "No external time source (source: '$source')"
        exit 1
    }
    $offset = Get-TimeOffsetSeconds $source
    if ($null -eq $offset) {
        Write-Output "Could not measure offset to $source"
        exit 1
    }
    if ([math]::Abs($offset) -gt $MaxSkewSeconds) {
        Write-Output ("Clock skew {0:N1}s from {1} (limit {2}s)" -f $offset, $source, $MaxSkewSeconds)
        exit 1
    }
    Write-Output ("OK: {0:N2}s from {1}" -f $offset, $source)
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
