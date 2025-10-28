<#
.SYNOPSIS
  Diagnoses and repairs common DNS/Winsock issues on Windows.
.PARAMETER Show
  Show current DNS, hosts file summary, and resolver status.
.PARAMETER Repair
  Flush DNS, reset Winsock, and reset IP stack.
.PARAMETER SetDns
  Set DNS servers on an interface by name.
.PARAMETER Interface
  Interface alias (e.g., "Ethernet"). Required with -SetDns.
.PARAMETER DnsServers
  One or more DNS server IPs. Required with -SetDns.
.EXAMPLE
  .\Fix-DnsStack.ps1 -Show
  .\Fix-DnsStack.ps1 -Repair
  .\Fix-DnsStack.ps1 -SetDns -Interface "Ethernet" -DnsServers 1.1.1.1, 8.8.8.8
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$Show,
  [switch]$Repair,
  [switch]$SetDns,
  [string]$Interface,
  [string[]]$DnsServers
)

function Show-State {
  "=== IPConfig /all ==="
  ipconfig /all
  "`n=== Hosts file (non-comment lines) ==="
  Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" | Where-Object { $_ -and $_ -notmatch '^\s*#' }
  "`n=== Test name resolution (example: registry-1.docker.io) ==="
  Resolve-DnsName registry-1.docker.io -ErrorAction SilentlyContinue
}

if ($Show) { Show-State; return }

if ($Repair) {
  if ($PSCmdlet.ShouldProcess("Network Stack","Repair")) {
    ipconfig /flushdns
    netsh winsock reset
    netsh int ip reset
    Write-Host "Repair commands executed. A reboot may be required."
  }
  return
}

if ($SetDns) {
  if (-not $Interface -or -not $DnsServers) { throw "Use -Interface and -DnsServers with -SetDns." }
  if ($PSCmdlet.ShouldProcess("DNS","Set servers on '$Interface' -> $($DnsServers -join ', ')")) {
    Set-DnsClientServerAddress -InterfaceAlias $Interface -ServerAddresses $DnsServers -ErrorAction Stop
    Write-Host "DNS servers updated on '$Interface'."
  }
  return
}

Write-Host "Nothing to do. Use -Show, -Repair, or -SetDns with -Interface/-DnsServers."
