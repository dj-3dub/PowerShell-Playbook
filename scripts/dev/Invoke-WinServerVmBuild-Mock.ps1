[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$VMName,
  [string]$Template = "Win2022-Base",
  [string]$Datacenter = "DC1",
  [string]$Cluster = "Prod-Cluster01",
  [string]$Datastore = "Datastore01",
  [int]$CPU = 4,
  [int]$MemoryGB = 16,
  [int]$DiskGB = 120,

  # 4 NICs -> 2 teams (A & B)
  [string]$PortGroup1 = "VM-Network-A",
  [string]$PortGroup2 = "VM-Network-B",
  [string]$PortGroup3 = "VM-Network-A",
  [string]$PortGroup4 = "VM-Network-B",

  # (Optional) guest settings to preview
  [string]$Hostname = $VMName,
  [string]$IPv4 = "192.168.10.50",
  [string]$PrefixLength = "24",
  [string]$Gateway = "192.168.10.1",
  [string[]]$DnsServers = @("192.168.10.10","1.1.1.1"),

  [string]$OutputPath = "./out"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'

# --- Simulated plan (what a real deploy would do) ---
$steps = @()

$steps += [pscustomobject]@{
  Order = 10; Area="vCenter"; Action="Validate Inputs"
  Detail="Check template [$Template], cluster [$Cluster], datastore [$Datastore] exist"
}
$steps += [pscustomobject]@{
  Order = 20; Area="vCenter"; Action="Clone VM"
  Detail="New-VM -Name $VMName -Template $Template -Datastore $Datastore -VMHost (best host in $Cluster)"
}
$steps += [pscustomobject]@{
  Order = 30; Area="vCenter"; Action="Set Hardware"
  Detail="Set-VM -Name $VMName -NumCpu $CPU -MemoryGB $MemoryGB; Set-HardDisk -CapacityGB $DiskGB"
}
$steps += [pscustomobject]@{
  Order = 40; Area="vCenter"; Action="Attach 4 NICs"
  Detail="Add-NetworkAdapter (PG1=$PortGroup1, PG2=$PortGroup2, PG3=$PortGroup3, PG4=$PortGroup4)"
}
$steps += [pscustomobject]@{
  Order = 50; Area="GuestOS"; Action="Create Teams"
  Detail="Create TeamA (NIC1+NIC3) and TeamB (NIC2+NIC4) — LACP/Static per standard"
}
$steps += [pscustomobject]@{
  Order = 60; Area="GuestOS"; Action="IP Config"
  Detail="Hostname=$Hostname IPv4=$IPv4/$PrefixLength GW=$Gateway DNS=$(($DnsServers -join ', '))"
}
$steps += [pscustomobject]@{
  Order = 70; Area="GuestOS"; Action="Post-Build"
  Detail="Join domain (optional), enable WinRM, install agent(s), apply baseline"
}

$summary = [pscustomobject]@{
  Stamp    = $stamp
  VMName   = $VMName
  Template = $Template
  Location = [pscustomobject]@{ Datacenter=$Datacenter; Cluster=$Cluster; Datastore=$Datastore }
  Sizing   = [pscustomobject]@{ CPU=$CPU; MemoryGB=$MemoryGB; DiskGB=$DiskGB }
  Networks = [pscustomobject]@{
    NICs = @(
      @{ Index=1; PortGroup=$PortGroup1 },
      @{ Index=2; PortGroup=$PortGroup2 },
      @{ Index=3; PortGroup=$PortGroup3 },
      @{ Index=4; PortGroup=$PortGroup4 }
    )
    Teams = @(
      @{ Name="TeamA"; Members="NIC1,NIC3" },
      @{ Name="TeamB"; Members="NIC2,NIC4" }
    )
  }
  GuestConfig = [pscustomobject]@{
    Hostname=$Hostname; IPv4=$IPv4; Prefix=$PrefixLength; Gateway=$Gateway; DnsServers=$DnsServers
  }
  Steps = $steps
}

# --- Outputs ---
$jsonPath = Join-Path $OutputPath "Mock-Deploy-$($VMName)-$stamp.json"
$htmlPath = Join-Path $OutputPath "Mock-Deploy-$($VMName)-$stamp.html"

$summary | ConvertTo-Json -Depth 6 | Out-File -Encoding UTF8 $jsonPath

$pre = @"
<h2>Mock VM Deployment Plan</h2>
<p><b>Generated:</b> $(Get-Date)</p>
<h3>Summary</h3>
<ul>
  <li><b>VM Name:</b> $VMName</li>
  <li><b>Template:</b> $Template</li>
  <li><b>Location:</b> DC=$Datacenter, Cluster=$Cluster, Datastore=$Datastore</li>
  <li><b>Sizing:</b> CPU=$CPU, Memory=$MemoryGB GB, Disk=$DiskGB GB</li>
  <li><b>NICs:</b> $PortGroup1 | $PortGroup2 | $PortGroup3 | $PortGroup4</li>
  <li><b>Teams:</b> TeamA(NIC1+NIC3), TeamB(NIC2+NIC4)</li>
  <li><b>Guest IP:</b> $IPv4/$PrefixLength (GW=$Gateway, DNS=$(($DnsServers -join ', ')))</li>
</ul>
<h3>Steps</h3>
"@

$steps |
  Sort-Object Order |
  Select-Object Order, Area, Action, Detail |
  ConvertTo-Html -Title "Mock VM Deployment Plan ($VMName)" -PreContent $pre |
  Out-File -Encoding UTF8 $htmlPath

Write-Host ("Plan JSON : {0}" -f $jsonPath)
Write-Host ("Plan HTML : {0}" -f $htmlPath)
return $summary
