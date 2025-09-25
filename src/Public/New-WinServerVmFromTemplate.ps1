function New-WinServerVmFromTemplate {
<#
.SYNOPSIS
Deploy a Windows Server VM from a vSphere template, attach 4 vNICs, and create two LBFO NIC teams inside the guest.

.DESCRIPTION
- Clones a VM from an existing template.
- Ensures the VM has 4 vmxnet3 adapters and powers it on.
- Inside the guest: creates two LBFO teams (2 NICs each) using SwitchIndependent + Dynamic.
- Optionally configures DHCP or static IPv4 on each team.
- Optionally joins an AD domain (guest must have local admin GuestCredential).

.REQUIREMENTS
- PowerCLI (VMware.VimAutomation.Core)
- VMware Tools installed in the Windows template
- Windows Server guest that supports LBFO (New-NetLbfoTeam)
- Guest local admin credentials (for in-guest config)

.PARAMETER VCenter
FQDN or IP of vCenter.

.PARAMETER VCenterCredential
Credential for Connect-VIServer.

.PARAMETER Datacenter
Target vSphere Datacenter name.

.PARAMETER Cluster
Target vSphere Cluster name. (Alternative: -VMHost can be used.)

.PARAMETER VMHost
Target ESXi host name. If omitted, the function picks the first host in -Cluster.

.PARAMETER Datastore
Target datastore for the VM.

.PARAMETER Folder
Destination vSphere folder (optional).

.PARAMETER TemplateName
Name of the Windows template to clone.

.PARAMETER VMName
New VM name.

.PARAMETER Cpu
vCPU count.

.PARAMETER MemoryGB
Memory in GB.

.PARAMETER DiskGB
Optional: resize the primary disk to this size (GB) if larger than template.

.PARAMETER CustomizationSpec
Optional vSphere OS customization spec name.

.PARAMETER NetworkNames
An array of 4 port group names. If you pass one name, it will be reused 4 times.

.PARAMETER GuestCredential
Local admin credential in the guest (for Invoke-VMScript steps).

.PARAMETER TeamsUseDhcp
If set, both teams are set to DHCP (static parameters are ignored).

.PARAMETER TeamAName
LBFO team name A (default: TeamA).

.PARAMETER TeamBName
LBFO team name B (default: TeamB).

.PARAMETER TeamAStaticIP / TeamASubnetMask / TeamAGateway / TeamADns
Optional static config for TeamA.

.PARAMETER TeamBStaticIP / TeamBSubnetMask / TeamBGateway / TeamBDns
Optional static config for TeamB.

.PARAMETER DomainName / DomainCredential / OUPath
Optional AD domain join settings. Requires GuestCredential to be local admin.

.EXAMPLE
New-WinServerVmFromTemplate -VCenter vcsa.lab.local -VCenterCredential (Get-Credential) `
  -Datacenter DC01 -Cluster Prod -Datastore vsanDatastore `
  -TemplateName WS2022-Base -VMName SRV-WEB-01 -Cpu 4 -MemoryGB 16 `
  -NetworkNames @('Servers-VLAN50') -TeamsUseDhcp `
  -GuestCredential (Get-Credential 'Administrator') -Verbose

.EXAMPLE
New-WinServerVmFromTemplate -VCenter vcsa.lab.local -VCenterCredential (Get-Credential) `
  -Datacenter DC01 -Cluster Prod -Datastore vsanDatastore -Folder "Prod/Windows" `
  -TemplateName WS2022-Base -VMName SRV-DB-01 -Cpu 8 -MemoryGB 32 -DiskGB 200 `
  -NetworkNames @('Prod-VLAN50','Prod-VLAN50','Backup-VLAN60','Backup-VLAN60') `
  -TeamAName ProdTeam -TeamAStaticIP 10.50.10.42 -TeamASubnetMask 255.255.255.0 -TeamAGateway 10.50.10.1 -TeamADns 10.50.10.10,10.50.10.11 `
  -TeamBName BackupTeam -TeamBStaticIP 10.60.10.42 -TeamBSubnetMask 255.255.255.0 -TeamBGateway 10.60.10.1 -TeamBDns 10.50.10.10,10.50.10.11 `
  -GuestCredential (Get-Credential 'Administrator') -Verbose
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$VCenter,
        [Parameter(Mandatory)] [pscredential]$VCenterCredential,

        [Parameter(Mandatory)] [string]$Datacenter,
        [string]$Cluster,
        [string]$VMHost,
        [Parameter(Mandatory)] [string]$Datastore,
        [string]$Folder,

        [Parameter(Mandatory)] [string]$TemplateName,
        [Parameter(Mandatory)] [string]$VMName,
        [Parameter(Mandatory)] [int]$Cpu,
        [Parameter(Mandatory)] [int]$MemoryGB,
        [int]$DiskGB,
        [string]$CustomizationSpec,

        [string[]]$NetworkNames,
        [Parameter(Mandatory)] [pscredential]$GuestCredential,

        [switch]$TeamsUseDhcp,
        [string]$TeamAName = 'TeamA',
        [string]$TeamBName = 'TeamB',

        [string]$TeamAStaticIP,
        [string]$TeamASubnetMask,
        [string]$TeamAGateway,
        [string[]]$TeamADns,

        [string]$TeamBStaticIP,
        [string]$TeamBSubnetMask,
        [string]$TeamBGateway,
        [string[]]$TeamBDns,

        [string]$DomainName,
        [pscredential]$DomainCredential,
        [string]$OUPath
    )

    begin {
        # Preconditions
        if (-not (Get-Module -Name VMware.VimAutomation.Core -ListAvailable)) {
            throw "PowerCLI is required. Install-Module VMware.PowerCLI -Scope CurrentUser"
        }
        Import-Module VMware.VimAutomation.Core -ErrorAction Stop

        # Normalize NetworkNames -> 4 items
        if (-not $NetworkNames -or $NetworkNames.Count -eq 0) {
            throw "Provide -NetworkNames with at least 1 item. If one item is given it will be reused 4x."
        }
        if ($NetworkNames.Count -eq 1) { $NetworkNames = @($NetworkNames[0],$NetworkNames[0],$NetworkNames[0],$NetworkNames[0]) }
        if ($NetworkNames.Count -lt 4) { throw "-NetworkNames must contain 4 items (one per vNIC)." }

        # Optional safety on static IPs
        if (-not $TeamsUseDhcp) {
            foreach ($pair in @(
                @{ip=$TeamAStaticIP; mask=$TeamASubnetMask},
                @{ip=$TeamBStaticIP; mask=$TeamBSubnetMask}
            )) {
                if ([string]::IsNullOrWhiteSpace($pair.ip) -xor [string]::IsNullOrWhiteSpace($pair.mask)) {
                    throw "If using static, both IP and SubnetMask must be provided for each team."
                }
            }
        }
    }

    process {
        # Connect to vCenter (skip if already connected to the same server)
        $connected = $false
        try {
            $current = Get-View ServiceInstance -ErrorAction SilentlyContinue
            if ($current) {
                # Allow existing session
                $connected = $true
            }
        } catch {}
        if (-not $connected) {
            Write-Verbose "Connecting to vCenter $VCenter ..."
            Connect-VIServer -Server $VCenter -Credential $VCenterCredential -ErrorAction Stop | Out-Null
        }

        # Resolve objects
        $dc = Get-Datacenter -Name $Datacenter -ErrorAction Stop
        $ds = Get-Datastore  -Name $Datastore  -Location $dc -ErrorAction Stop
        $template = Get-Template -Name $TemplateName -Location $dc -ErrorAction Stop

        # Pick host or host from cluster
        $targetHost = $null
        if ($VMHost) {
            $targetHost = Get-VMHost -Name $VMHost -Location $dc -ErrorAction Stop
        } elseif ($Cluster) {
            $cl = Get-Cluster -Name $Cluster -Location $dc -ErrorAction Stop
            $targetHost = Get-VMHost -Location $cl | Sort-Object CpuUsageMhz | Select-Object -First 1
        } else {
            throw "Specify either -Cluster or -VMHost for placement."
        }

        $newVmParams = @{
            Name        = $VMName
            Template    = $template
            VMHost      = $targetHost
            Datastore   = $ds
            ErrorAction = 'Stop'
        }
        if ($Folder) { $newVmParams.Folder = (Get-Folder -Name $Folder -Location $dc -ErrorAction Stop) }
        if ($CustomizationSpec) { $newVmParams.OSCustomizationSpec = $CustomizationSpec }

        if ($PSCmdlet.ShouldProcess($VMName, "Clone from template")) {
            Write-Verbose "Cloning VM $VMName from template $TemplateName ..."
            $vm = New-VM @newVmParams

            # CPU/Memory
            if ($vm.NumCpu -ne $Cpu) {
                Set-VM -VM $vm -NumCpu $Cpu -Confirm:$false | Out-Null
            }
            if ($vm.MemoryGB -ne $MemoryGB) {
                Set-VM -VM $vm -MemoryGB $MemoryGB -Confirm:$false | Out-Null
            }

            # Disk grow (if requested and larger than current)
            if ($DiskGB -gt 0) {
                $disk = Get-HardDisk -VM $vm | Select-Object -First 1
                if ($disk.CapacityGB -lt $DiskGB) {
                    Write-Verbose "Expanding disk from $($disk.CapacityGB)GB to $DiskGB GB ..."
                    Set-HardDisk -HardDisk $disk -CapacityGB $DiskGB -Confirm:$false | Out-Null
                }
            }

            # Remove default NIC(s) New-VM might add
            Get-NetworkAdapter -VM $vm -ErrorAction SilentlyContinue | Remove-NetworkAdapter -Confirm:$false | Out-Null

            # Add 4 vmxnet3 adapters
            for ($i=0; $i -lt 4; $i++) {
                New-NetworkAdapter -VM $vm -NetworkName $NetworkNames[$i] -Type vmxnet3 -StartConnected -Confirm:$false | Out-Null
            }

            # Power on & wait for tools
            Start-VM -VM $vm -Confirm:$false | Out-Null
            Write-Verbose "Waiting for VMware Tools..."
            Wait-Tools -VM $vm -ErrorAction Stop

            # Inside guest: domain join (optional) then NIC teaming + IP config
            $guestVars = @{
                TeamAName  = $TeamAName
                TeamBName  = $TeamBName
                UseDhcp    = [bool]$TeamsUseDhcp
                A_IP       = [string]$TeamAStaticIP
                A_Mask     = [string]$TeamASubnetMask
                A_Gw       = [string]$TeamAGateway
                A_DnsCsv   = ($TeamADns -join ',')
                B_IP       = [string]$TeamBStaticIP
                B_Mask     = [string]$TeamBSubnetMask
                B_Gw       = [string]$TeamBGateway
                B_DnsCsv   = ($TeamBDns -join ',')
                DomainName = $DomainName
                OUPath     = $OUPath
                DoJoin     = [bool]([string]::IsNullOrWhiteSpace($DomainName) -eq $false -and $DomainCredential)
                DomUser    = if ($DomainCredential) { $DomainCredential.UserName } else { "" }
                DomPass    = if ($DomainCredential) { $DomainCredential.GetNetworkCredential().Password } else { "" }
            }

            # Build guest script (PowerShell). Note: credentials are passed in-process; do not reuse in production without vaulting.
$guestScript = @"
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine -Force

function Convert-MaskToPrefix([string]\$Mask) {
    if (-not \$Mask) { return \$null }
    \$bits = (\$Mask -split '\.') | ForEach-Object {
        [Convert]::ToString([int]\$_,2).PadLeft(8,'0')
    } -join ''
    return (\$bits.ToCharArray() | Where-Object { \$_ -eq '1' }).Count
}

# Optional domain join
if (${($guestVars.DoJoin.ToString().ToLower())}) {
    try {
        \$sec = ConvertTo-SecureString '${($guestVars.DomPass)}' -AsPlainText -Force
        \$cred = New-Object System.Management.Automation.PSCredential ('${($guestVars.DomUser)}', \$sec)
        \$joinArgs = @{ 'DomainName'='${($guestVars.DomainName)}'; 'Credential'=\$cred; 'ErrorAction'='Stop' }
        if ('${($guestVars.OUPath)}') { \$joinArgs['OUPath'] = '${($guestVars.OUPath)}' }
        Add-Computer @joinArgs
        # Do NOT reboot automatically; caller can handle maintenance window reboots.
    } catch {
        Write-Host "Domain join failed: \$($_.Exception.Message)"
    }
}

# Collect first 4 physical 'Up' NICs
\$nics = Get-NetAdapter -Physical | Where-Object { \$_.Status -eq 'Up' } | Sort-Object Name | Select-Object -First 4
if (-not \$nics -or \$nics.Count -lt 4) { throw 'Expected 4 Up physical adapters in guest.' }

# Create teams if missing
if (-not (Get-NetLbfoTeam -Name '${($guestVars.TeamAName)}' -ErrorAction SilentlyContinue)) {
    New-NetLbfoTeam -Name '${($guestVars.TeamAName)}' -TeamMembers \$nics[0].Name, \$nics[1].Name -TeamingMode SwitchIndependent -LoadBalancingAlgorithm Dynamic | Out-Null
}
if (-not (Get-NetLbfoTeam -Name '${($guestVars.TeamBName)}' -ErrorAction SilentlyContinue)) {
    New-NetLbfoTeam -Name '${($guestVars.TeamBName)}' -TeamMembers \$nics[2].Name, \$nics[3].Name -TeamingMode SwitchIndependent -LoadBalancingAlgorithm Dynamic | Out-Null
}

function Set-TeamIp(\$alias, \$staticIp, \$mask, \$gw, \$dnsCsv, \$dhcp) {
    if (\$dhcp -or [string]::IsNullOrWhiteSpace(\$staticIp)) {
        try { Set-NetIPInterface -InterfaceAlias \$alias -Dhcp Enabled -ErrorAction Stop } catch {}
        try { Set-DnsClientServerAddress -InterfaceAlias \$alias -ResetServerAddresses -ErrorAction SilentlyContinue } catch {}
        return
    }
    \$prefix = Convert-MaskToPrefix \$mask
    if (-not \$prefix) { throw "Cannot compute prefix from mask: \$mask" }

    Get-NetIPAddress -InterfaceAlias \$alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:\$false -ErrorAction SilentlyContinue

    New-NetIPAddress -InterfaceAlias \$alias -IPAddress \$staticIp -PrefixLength \$prefix -DefaultGateway \$gw -ErrorAction Stop
    if (-not [string]::IsNullOrWhiteSpace(\$dnsCsv)) {
        \$dns = \$dnsCsv -split ','
        Set-DnsClientServerAddress -InterfaceAlias \$alias -ServerAddresses \$dns -ErrorAction SilentlyContinue
    }
}

Set-TeamIp '${($guestVars.TeamAName)}' '${($guestVars.A_IP)}' '${($guestVars.A_Mask)}' '${($guestVars.A_Gw)}' '${($guestVars.A_DnsCsv)}' ${($guestVars.UseDhcp.ToString().ToLower())}
Set-TeamIp '${($guestVars.TeamBName)}' '${($guestVars.B_IP)}' '${($guestVars.B_Mask)}' '${($guestVars.B_Gw)}' '${($guestVars.B_DnsCsv)}' ${($guestVars.UseDhcp.ToString().ToLower())}

# Basic validation
Get-NetLbfoTeam | Format-List *
Get-NetIPConfiguration | Format-List InterfaceAlias,IPv4Address,IPv4DefaultGateway,DnsServer
"@

            Write-Verbose "Configuring guest (teaming + IPs)..."
            Invoke-VMScript -VM $vm -ScriptText $guestScript -ScriptType Powershell -GuestCredential $GuestCredential -ErrorAction Stop | Out-Null

            # Return a summary object
            [pscustomobject]@{
                VMName      = $vm.Name
                PowerState  = $vm.PowerState.ToString()
                Cpu         = $Cpu
                MemoryGB    = $MemoryGB
                Datastore   = $Datastore
                Host        = $targetHost.Name
                Networks    = ($NetworkNames -join ', ')
                TeamsDhcp   = [bool]$TeamsUseDhcp
                TeamA       = $TeamAName
                TeamB       = $TeamBName
                DomainJoin  = if ($guestVars.DoJoin) { $DomainName } else { $null }
            }
        }
    }

    end {}
}
