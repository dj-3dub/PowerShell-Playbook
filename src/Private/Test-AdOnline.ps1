function Test-AdOnline {
    <#
    .SYNOPSIS
    Checks if an AD endpoint is reachable (ADWS/TCP 9389) and returns a hashtable with connection parameters.
    .PARAMETER Server
    Domain FQDN or DC hostname. If omitted and machine is domain-joined, discovery is used. If not joined, you must pass -Server.
    .PARAMETER Credential
    PSCredential for AD bind when not domain-joined or when the current context lacks rights.
    .OUTPUTS
    [hashtable] @{ Online = [bool]; Server = [string]; Credential = [PSCredential] }
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [System.Management.Automation.PSCredential]$Credential
    )

    $result = @{
        Online     = $false
        Server     = $null
        Credential = $Credential
    }

    # If no server supplied, try to infer when domain-joined
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $joined = [bool]$cs.PartOfDomain
        if (-not $Server) {
            if ($joined) {
                # try discovery
                try {
                    $dc = Get-ADDomainController -Discover -Service ADWS -ErrorAction Stop
                    $Server = $dc.HostName
                } catch {
                    # fall back to domain FQDN if available
                    if ($cs.Domain) { $Server = $cs.Domain }
                }
            }
        }
    } catch { }

    if (-not $Server) { return $result } # not joined and no server passed

    # Check ADWS port 9389
    try {
        $ok = Test-NetConnection -ComputerName $Server -Port 9389 -WarningAction SilentlyContinue
        if ($ok.TcpTestSucceeded) {
            $result.Online = $true
            $result.Server = $Server
        }
    } catch { }

    return $result
}
