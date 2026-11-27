<#
.SYNOPSIS
  PowerShell Playbook extensions: infrastructure and cloud health reports.

.DESCRIPTION
  Functions:
    - Invoke-WindowsUpdateBaseline : patch compliance from Intune (Graph), ConfigMgr (SMS provider) or the local Windows Update Agent
    - Test-BackupRestoreReadiness  : last Veeam backup result and age against an RPO threshold
    - Get-VMwareHealth             : vSphere host state, datastore free space and snapshot age
    - Get-CloudBaseline            : Azure / AWS hygiene (unattached disks, idle public IPs, old snapshots)
    - Get-O365TenantHealth         : Exchange Online security settings (audit log, external forwarding, modern auth)
    - Publish-ReportToTicket       : attach a report to a ticket through a generic REST API
    - New-PlaybookReport           : shared HTML report builder

  Behaviour shared by every report function:
    * Live by default. Each function uses the vendor module's existing session (Connect-MgGraph,
      Connect-AzAccount, Connect-ExchangeOnline, Connect-VIServer, ...). If the module or session is
      missing it returns a single 'NotConnected' row explaining what to do. It never invents data.
    * -Mock returns representative sample data, tagged Source = 'Mock', for demos and tests.
    * Rows carry a Status of OK / Warn / Fail (or Info / NotConnected); the HTML report colour-codes it.
    * Output: <OutputRoot>/<yyyy-MM-dd>/<FunctionName>/<Name>.csv and .html (OutputRoot defaults to ./out).
#>

Set-StrictMode -Version Latest

# -----------------------------------------------------------------------------
# Config (override in session: $m = Get-Module PowerShell-Playbook.Extensions; & $m { $script:PlaybookConfig.OutputRoot = 'D:\Reports' })
# -----------------------------------------------------------------------------
$script:PlaybookConfig = [ordered]@{
  OutputRoot = $null   # $null = ./out under the current directory at call time
  Ticketing  = [ordered]@{
    BaseUrl    = $env:TICKETS_BASE_URL   # e.g. https://servicedesk.example.com/api
    Token      = $env:TICKETS_API_TOKEN  # bearer token / PAT
    ProjectKey = $env:TICKETS_PROJECT    # optional
  }
}

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------
function New-PlaybookOutputPath {
  param(
    [Parameter(Mandatory)] [string] $FunctionName,
    [string] $Suffix = ''
  )
  $root = $script:PlaybookConfig.OutputRoot
  if (-not $root) { $root = Join-Path (Get-Location) 'out' }
  $path = Join-Path (Join-Path $root (Get-Date -Format 'yyyy-MM-dd')) $FunctionName
  if ($Suffix) { $path = Join-Path $path ($Suffix -replace '[\\/:*?"<>|]', '_') }
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  $path
}

function Test-PlaybookCommand {
  # True when every named command is available (module installed and importable).
  param([Parameter(Mandatory)] [string[]] $Name)
  foreach ($n in $Name) {
    if (-not (Get-Command -Name $n -ErrorAction SilentlyContinue)) { return $false }
  }
  $true
}

function New-NotConnectedRow {
  param([string] $Scope, [string] $Detail)
  [pscustomobject]@{ Scope = $Scope; Check = 'Connection'; Status = 'NotConnected'; Detail = $Detail; Source = 'Live' }
}

function Complete-PlaybookRun {
  # Writes CSV + HTML for a set of rows and returns a consistent result object.
  param(
    [Parameter(Mandatory)] [string] $OutDir,
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [string] $Title,
    [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Rows,
    [hashtable] $Meta = @{},
    [switch] $Mock
  )
  if ($Mock) { $Title = "$Title (sample data)" }
  $csv  = Join-Path $OutDir "$Name.csv"
  $html = Join-Path $OutDir "$Name.html"
  # -NoTypeInformation is required on 5.1 and obsolete (warns) on 7.x.
  $csvArgs = @{ Path = $csv; Encoding = 'UTF8' }
  if ($PSVersionTable.PSVersion.Major -lt 6) { $csvArgs.NoTypeInformation = $true }
  $Rows | Export-Csv @csvArgs
  New-PlaybookReport -Title $Title -Data $Rows -Meta $Meta -OutFile $html | Out-Null
  [pscustomobject]@{ Csv = $csv; Html = $html; Rows = $Rows }
}

function Get-ThresholdStatus {
  # OK below Warn, Warn at/above Warn, Fail at/above Fail (for "higher is worse" metrics).
  param([double] $Value, [double] $Warn, [double] $Fail)
  if ($Value -ge $Fail) { 'Fail' } elseif ($Value -ge $Warn) { 'Warn' } else { 'OK' }
}

# -----------------------------------------------------------------------------
# Shared HTML report builder
# -----------------------------------------------------------------------------
function New-PlaybookReport {
  <#
  .SYNOPSIS
    Build a consistent HTML report: title, metadata chips, a summary of Status counts, and a table.
  .PARAMETER Title
    Report title.
  .PARAMETER Data
    Objects to render as a table. A 'Status' column with OK/Warn/Fail/NotConnected values is colour-coded.
  .PARAMETER Meta
    Hashtable of key/value metadata shown under the title.
  .PARAMETER OutFile
    Path of the HTML file to write.
  .EXAMPLE
    New-PlaybookReport -Title 'Patch Baseline' -Data $rows -Meta @{ Scope = 'All Servers' } -OutFile 'report.html'
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Title,
    [Parameter(Mandatory)] [AllowEmptyCollection()] $Data,
    [hashtable] $Meta,
    [Parameter(Mandatory)] [string] $OutFile
  )
  $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }

  $style = @'
<style>
  :root { --fg:#1f2328; --muted:#656d76; --line:#d0d7de; --head:#f6f8fa;
          --ok:#1a7f37; --ok-bg:#dafbe1; --warn:#9a6700; --warn-bg:#fff8c5;
          --fail:#cf222e; --fail-bg:#ffebe9; --info:#0969da; --info-bg:#ddf4ff; }
  body { font-family: "Segoe UI", system-ui, -apple-system, Roboto, Arial, sans-serif; color: var(--fg); margin: 32px; }
  h1 { font-size: 22px; margin: 0 0 4px; }
  .subtle { color: var(--muted); font-size: 12px; }
  .chips { margin: 14px 0 6px; }
  .chip { display: inline-block; padding: 4px 10px; margin: 0 6px 6px 0; border: 1px solid var(--line);
          border-radius: 999px; font-size: 12px; background: #fff; }
  .chip b { font-weight: 600; }
  .summary .chip.ok   { color: var(--ok);   background: var(--ok-bg);   border-color: transparent; }
  .summary .chip.warn { color: var(--warn); background: var(--warn-bg); border-color: transparent; }
  .summary .chip.fail { color: var(--fail); background: var(--fail-bg); border-color: transparent; }
  .summary .chip.info { color: var(--info); background: var(--info-bg); border-color: transparent; }
  table { border-collapse: collapse; width: 100%; margin-top: 12px; font-size: 13px; }
  th, td { border-bottom: 1px solid var(--line); padding: 8px 10px; text-align: left; vertical-align: top; }
  th { background: var(--head); font-weight: 600; border-top: 1px solid var(--line); }
  tr:hover td { background: #fafbfc; }
  td.status { font-weight: 600; white-space: nowrap; }
  td.ok { color: var(--ok); } td.warn { color: var(--warn); } td.fail { color: var(--fail); } td.info { color: var(--info); }
  .footer { margin-top: 24px; font-size: 12px; color: var(--muted); }
</style>
'@

  $rows = @($Data)

  $metaHtml = ''
  if ($Meta) {
    $metaHtml = ($Meta.GetEnumerator() | Sort-Object Key | ForEach-Object {
        "<span class='chip'><b>$(& $enc $_.Key):</b> $(& $enc $_.Value)</span>"
      }) -join "`n"
  }

  $summaryHtml = ''
  if ($rows.Count -and $rows[0].PSObject.Properties['Status']) {
    $order = @{ OK = 0; Warn = 1; Fail = 2; Info = 3; NotConnected = 4 }
    $summaryHtml = ($rows | Group-Object Status | Sort-Object { if ($order.ContainsKey($_.Name)) { $order[$_.Name] } else { 9 } } | ForEach-Object {
        $cls = switch ($_.Name) { 'OK' { 'ok' } 'Warn' { 'warn' } 'Fail' { 'fail' } default { 'info' } }
        "<span class='chip $cls'>$(& $enc $_.Name): $($_.Count)</span>"
      }) -join "`n"
  }

  $table = ($rows | ConvertTo-Html -Fragment) -join "`n"
  # Colour-code Status cells (ConvertTo-Html already HTML-encodes cell values).
  $table = [regex]::Replace($table, '<td>(OK|Warn|Fail|NotConnected|Info)</td>', {
      param($m)
      $cls = switch ($m.Groups[1].Value) { 'OK' { 'ok' } 'Warn' { 'warn' } 'Fail' { 'fail' } default { 'info' } }
      "<td class=""status $cls"">$($m.Groups[1].Value)</td>"
    })

  $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
  $body = @"
<h1>$(& $enc $Title)</h1>
<div class='subtle'>Generated $generated on $(& $enc ([Environment]::MachineName))</div>
<div class='chips'>$metaHtml</div>
<div class='chips summary'>$summaryHtml</div>
$table
<div class='footer'>PowerShell Playbook &middot; github.com/dj-3dub/PowerShell-Playbook</div>
"@

  ConvertTo-Html -Head $style -Body $body -Title $Title | Out-File -Encoding UTF8 -FilePath $OutFile
  $OutFile
}

# -----------------------------------------------------------------------------
# Windows Update / patch compliance
# -----------------------------------------------------------------------------
function Invoke-WindowsUpdateBaseline {
  <#
  .SYNOPSIS
    Report Windows patch compliance (read-only).
  .DESCRIPTION
    -Provider Intune : Windows managed devices from Microsoft Graph (requires Connect-MgGraph with
                       DeviceManagementManagedDevices.Read.All). Flags non-compliant devices and stale check-ins.
    -Provider SCCM   : Required-but-missing update counts per device from the ConfigMgr SMS provider
                       (SMS_UpdateComplianceStatus, Status = 2). Requires -SccmSiteServer and -SccmSiteCode.
    -Provider WSUS   : Scans THIS machine through the Windows Update Agent against its configured source
                       (WSUS or Windows Update) and reports pending updates and reboot state.
  .PARAMETER StaleDays
    Intune: devices that have not synced in this many days are flagged Warn. Default 7.
  .PARAMETER Mock
    Return sample data instead of querying a live system.
  .EXAMPLE
    Connect-MgGraph -Scopes DeviceManagementManagedDevices.Read.All; Invoke-WindowsUpdateBaseline -Provider Intune
  .EXAMPLE
    Invoke-WindowsUpdateBaseline -Provider SCCM -SccmSiteServer cm01 -SccmSiteCode P01
  #>
  [CmdletBinding()]
  param(
    [ValidateSet('Intune', 'SCCM', 'WSUS')] [string] $Provider = 'Intune',
    [string] $SccmSiteServer,
    [string] $SccmSiteCode,
    [ValidateRange(1, 365)] [int] $StaleDays = 7,
    [switch] $Mock
  )
  $outDir = New-PlaybookOutputPath -FunctionName $MyInvocation.MyCommand.Name -Suffix $Provider
  $now = Get-Date

  $row = {
    param($HostName, $Status, $Pending, $Reboot, $LastScan, $Detail, $Source)
    [pscustomobject]@{
      Provider = $Provider; Host = $HostName; Status = $Status; PendingUpdates = $Pending
      RebootRequired = $Reboot; LastScan = $LastScan; Detail = $Detail; Source = $Source
    }
  }

  $rows = @(
    if ($Mock) {
      & $row 'WS-0142' 'OK'   0 $false $now.AddHours(-5)  'Compliant'                   'Mock'
      & $row 'WS-0187' 'Warn' 3 $true  $now.AddDays(-2)   'Pending reboot'              'Mock'
      & $row 'WS-0203' 'Fail' 9 $false $now.AddDays(-19)  'Non-compliant; stale check-in' 'Mock'
      & $row 'SRV-FS01' 'OK'  0 $false $now.AddHours(-11) 'Compliant'                   'Mock'
    }
    else {
      switch ($Provider) {
        'Intune' {
          if (-not (Test-PlaybookCommand 'Get-MgContext', 'Get-MgDeviceManagementManagedDevice')) {
            New-NotConnectedRow 'Intune' 'Install-Module Microsoft.Graph.DeviceManagement, then Connect-MgGraph -Scopes DeviceManagementManagedDevices.Read.All'
          }
          elseif (-not (Get-MgContext)) {
            New-NotConnectedRow 'Intune' 'No Graph session. Run Connect-MgGraph -Scopes DeviceManagementManagedDevices.Read.All'
          }
          else {
            Get-MgDeviceManagementManagedDevice -All -Filter "operatingSystem eq 'Windows'" |
              ForEach-Object {
                # Devices that never checked in have no LastSyncDateTime; treat them as maximally stale.
                $age = if ($_.LastSyncDateTime) { ($now - $_.LastSyncDateTime).TotalDays } else { [double]::PositiveInfinity }
                $status = if ($_.ComplianceState -eq 'noncompliant') { 'Fail' } elseif ($age -gt $StaleDays) { 'Warn' } else { 'OK' }
                $detail = '{0}; OS {1}; last sync {2:N0} day(s) ago' -f $_.ComplianceState, $_.OSVersion, $age
                & $row $_.DeviceName $status $null $null $_.LastSyncDateTime $detail 'Live'
              }
          }
        }
        'SCCM' {
          if (-not $SccmSiteServer -or -not $SccmSiteCode) {
            throw 'SCCM provider requires -SccmSiteServer and -SccmSiteCode.'
          }
          $cim = @{ ComputerName = $SccmSiteServer; Namespace = "root\SMS\site_$SccmSiteCode"; ErrorAction = 'Stop' }
          $names = @{}
          Get-CimInstance @cim -ClassName SMS_R_System -Property ResourceID, Name |
            ForEach-Object { $names[[int]$_.ResourceID] = $_.Name }
          # Status 2 = update is applicable and required (missing) on the device.
          $missing = Get-CimInstance @cim -ClassName SMS_UpdateComplianceStatus -Filter 'Status = 2' -Property MachineID |
            Group-Object MachineID
          foreach ($g in $missing) {
            $count = $g.Count
            $hostName = $names[[int]$g.Name]
            if (-not $hostName) { $hostName = "ResourceID $($g.Name)" }
            & $row $hostName (Get-ThresholdStatus $count 1 5) $count $null $null "$count required update(s) missing" 'Live'
          }
          if (-not $missing) { & $row $SccmSiteServer 'OK' 0 $null $null 'No devices report missing required updates' 'Live' }
        }
        'WSUS' {
          if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
            New-NotConnectedRow 'WSUS' 'The Windows Update Agent is only available on Windows.'
          }
          else {
            $session  = New-Object -ComObject Microsoft.Update.Session
            $result   = $session.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Software' and IsHidden=0")
            $pending  = [int]$result.Updates.Count
            $reboot   = [bool](New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired
            $status   = if ($pending -ge 5) { 'Fail' } elseif ($pending -gt 0 -or $reboot) { 'Warn' } else { 'OK' }
            $titles   = @($result.Updates | Select-Object -First 5 -ExpandProperty Title) -join '; '
            & $row $env:COMPUTERNAME $status $pending $reboot $now $titles 'Live'
          }
        }
      }
    }
  )

  Complete-PlaybookRun -OutDir $outDir -Name 'WindowsUpdateBaseline' -Title 'Windows Update Baseline' -Rows $rows `
    -Meta @{ Provider = $Provider; StaleDays = $StaleDays } -Mock:$Mock
}

# -----------------------------------------------------------------------------
# Backup readiness
# -----------------------------------------------------------------------------
function Test-BackupRestoreReadiness {
  <#
  .SYNOPSIS
    Check that the most recent Veeam backup of a job succeeded and is within the RPO.
  .DESCRIPTION
    Uses Veeam Backup & Replication PowerShell (v11+) on the backup server or a console machine.
    Status: OK = last session Success within -MaxAgeHours; Warn = Warning result, or older than the RPO;
    Fail = Failed, or no session found. Session details are written to an evidence file next to the report.
    This does not perform a restore; pair it with SureBackup or a scheduled restore drill.
  .PARAMETER JobName
    Veeam backup job name(s).
  .PARAMETER MaxAgeHours
    Recovery point objective in hours. Default 26 (daily job plus slack).
  .EXAMPLE
    Test-BackupRestoreReadiness -JobName 'Daily - File Servers','Daily - SQL'
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string[]] $JobName,
    [ValidateRange(1, 8760)] [int] $MaxAgeHours = 26,
    [switch] $Mock
  )
  $outDir = New-PlaybookOutputPath -FunctionName $MyInvocation.MyCommand.Name
  $now = Get-Date

  $classify = {
    param($Job, $Result, $End)
    if (-not $End) { return [pscustomobject]@{ Job = $Job; Status = 'Fail'; LastResult = 'NoSession'; LastEnd = $null; AgeHours = $null; Detail = 'No backup session found' } }
    $age = [math]::Round(($now - $End).TotalHours, 1)
    $status = if ($Result -eq 'Failed') { 'Fail' } elseif ($Result -eq 'Warning' -or $age -gt $MaxAgeHours) { 'Warn' } else { 'OK' }
    $detail = if ($age -gt $MaxAgeHours) { "Older than RPO ($MaxAgeHours h)" } else { "Within RPO ($MaxAgeHours h)" }
    [pscustomobject]@{ Job = $Job; Status = $status; LastResult = $Result; LastEnd = $End; AgeHours = $age; Detail = $detail }
  }

  $rows = @(
    if ($Mock) {
      $samples = @(
        @('Success', $now.AddHours(-9)), @('Warning', $now.AddHours(-20)), @('Success', $now.AddHours(-71)), @('Failed', $now.AddHours(-8))
      )
      $i = 0
      foreach ($j in $JobName) {
        $s = $samples[$i % $samples.Count]; $i++
        $r = & $classify $j $s[0] $s[1]; $r | Add-Member Source 'Mock' -PassThru
      }
    }
    elseif (-not (Test-PlaybookCommand 'Get-VBRJob', 'Get-VBRBackupSession')) {
      New-NotConnectedRow 'Veeam' 'Run on a Veeam B&R server/console (Veeam.Backup.PowerShell), then Connect-VBRServer if remote.'
    }
    else {
      foreach ($j in $JobName) {
        $last = Get-VBRBackupSession | Where-Object { $_.JobName -eq $j } |
          Sort-Object EndTime -Descending | Select-Object -First 1
        if ($last) { $r = & $classify $j ([string]$last.Result) $last.EndTime } else { $r = & $classify $j $null $null }
        $r | Add-Member Source 'Live' -PassThru
      }
    }
  )

  $evidence = Join-Path $outDir 'backup-evidence.json'
  [pscustomobject]@{ CheckedAt = $now; MaxAgeHours = $MaxAgeHours; Sessions = $rows } |
    ConvertTo-Json -Depth 4 | Out-File -FilePath $evidence -Encoding UTF8

  $result = Complete-PlaybookRun -OutDir $outDir -Name 'BackupRestoreReadiness' -Title 'Backup Readiness' -Rows $rows `
    -Meta @{ RPOHours = $MaxAgeHours; Jobs = $JobName.Count } -Mock:$Mock
  $result | Add-Member Evidence $evidence -PassThru
}

# -----------------------------------------------------------------------------
# VMware vSphere
# -----------------------------------------------------------------------------
function Get-VMwareHealth {
  <#
  .SYNOPSIS
    vSphere health: host connection state, datastore free space, and snapshot age.
  .PARAMETER Server
    vCenter/ESXi FQDN.
  .PARAMETER Credential
    Credential for Connect-VIServer (omit to use the current session / SSO).
  .PARAMETER DatastoreFreeWarnPct
    Datastores below this % free are Warn; below half of it, Fail. Default 20.
  .PARAMETER SnapshotWarnDays
    Snapshots older than this are Warn; older than 3x, Fail. Default 3.
  .EXAMPLE
    Get-VMwareHealth -Server vcsa01.corp.example.com -Credential (Get-Credential)
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Server,
    [System.Management.Automation.PSCredential] $Credential,
    [ValidateRange(1, 99)] [int] $DatastoreFreeWarnPct = 20,
    [ValidateRange(1, 365)] [int] $SnapshotWarnDays = 3,
    [switch] $Mock
  )
  $outDir = New-PlaybookOutputPath -FunctionName $MyInvocation.MyCommand.Name -Suffix $Server
  $now = Get-Date

  $dsRow = {
    param($Name, $CapGB, $FreeGB, $Source)
    $pct = [math]::Round(($FreeGB / $CapGB) * 100, 1)
    $status = if ($pct -lt ($DatastoreFreeWarnPct / 2)) { 'Fail' } elseif ($pct -lt $DatastoreFreeWarnPct) { 'Warn' } else { 'OK' }
    [pscustomobject]@{ Scope = 'Datastore'; Item = $Name; Status = $status; Detail = "$pct% free ($([math]::Round($FreeGB)) of $([math]::Round($CapGB)) GB)"; Source = $Source }
  }
  $snapRow = {
    param($Vm, $SnapName, $Created, $Source)
    $days = [math]::Floor(($now - $Created).TotalDays)
    $status = Get-ThresholdStatus $days ($SnapshotWarnDays + 1) ($SnapshotWarnDays * 3 + 1)
    [pscustomobject]@{ Scope = 'Snapshot'; Item = "$Vm / $SnapName"; Status = $status; Detail = "$days day(s) old"; Source = $Source }
  }
  $hostRow = {
    param($Name, $State, $Version, $Source)
    $status = if ($State -eq 'Connected') { 'OK' } elseif ($State -eq 'Maintenance') { 'Warn' } else { 'Fail' }
    [pscustomobject]@{ Scope = 'Host'; Item = $Name; Status = $status; Detail = "$State; ESXi $Version"; Source = $Source }
  }

  $rows = @(
    if ($Mock) {
      & $hostRow 'esx01.corp.example.com' 'Connected' '8.0.3' 'Mock'
      & $hostRow 'esx02.corp.example.com' 'Maintenance' '8.0.3' 'Mock'
      & $dsRow 'DS-PROD-01' 4096 1720 'Mock'
      & $dsRow 'DS-PROD-02' 4096 610 'Mock'
      & $dsRow 'DS-BACKUP' 8192 330 'Mock'
      & $snapRow 'SQL01' 'pre-patch' $now.AddDays(-1) 'Mock'
      & $snapRow 'APP03' 'before-upgrade' $now.AddDays(-12) 'Mock'
    }
    elseif (-not (Test-PlaybookCommand 'Connect-VIServer', 'Get-VMHost', 'Get-Datastore', 'Get-Snapshot')) {
      New-NotConnectedRow 'VMware' 'Install-Module VCF.PowerCLI (or VMware.PowerCLI) -Scope CurrentUser'
    }
    else {
      $connParams = @{ Server = $Server; ErrorAction = 'Stop' }
      if ($Credential) { $connParams.Credential = $Credential }
      $vi = Connect-VIServer @connParams
      try {
        Get-VMHost -Server $vi | ForEach-Object { & $hostRow $_.Name ([string]$_.ConnectionState) $_.Version 'Live' }
        Get-Datastore -Server $vi | Where-Object { $_.CapacityGB -gt 0 } |
          ForEach-Object { & $dsRow $_.Name $_.CapacityGB $_.FreeSpaceGB 'Live' }
        Get-VM -Server $vi | Get-Snapshot | ForEach-Object { & $snapRow $_.VM.Name $_.Name $_.Created 'Live' }
      }
      finally {
        Disconnect-VIServer -Server $vi -Confirm:$false -ErrorAction SilentlyContinue
      }
    }
  )

  Complete-PlaybookRun -OutDir $outDir -Name 'VMwareHealth' -Title 'VMware Health' -Rows $rows `
    -Meta @{ vCenter = $Server; DatastoreFreeWarnPct = $DatastoreFreeWarnPct; SnapshotWarnDays = $SnapshotWarnDays } -Mock:$Mock
}

# -----------------------------------------------------------------------------
# Cloud hygiene (Azure / AWS)
# -----------------------------------------------------------------------------
function Get-CloudBaseline {
  <#
  .SYNOPSIS
    Cloud cost/security hygiene: unattached disks, idle public IPs, old snapshots, VM inventory.
  .DESCRIPTION
    Azure: uses the current Az context (Connect-AzAccount). Checks VM count, unattached managed disks,
           and public IPs not associated with any resource.
    AWS:   uses the current AWS credential/profile and region. Checks EC2 instance count, unattached EBS
           volumes, and self-owned EBS snapshots older than -SnapshotMaxAgeDays.
  .EXAMPLE
    Connect-AzAccount; Get-CloudBaseline -Provider Azure
  .EXAMPLE
    Set-AWSCredential -ProfileName prod; Get-CloudBaseline -Provider AWS -Region us-east-1
  #>
  [CmdletBinding()]
  param(
    [ValidateSet('Azure', 'AWS', 'Both')] [string] $Provider = 'Azure',
    [string] $Region,
    [ValidateRange(1, 3650)] [int] $SnapshotMaxAgeDays = 90,
    [switch] $Mock
  )
  $outDir = New-PlaybookOutputPath -FunctionName $MyInvocation.MyCommand.Name -Suffix $Provider

  $finding = {
    param($Cloud, $Scope, $Check, $Count, $WarnAt, $Detail, $Source)
    $status = if ($null -eq $WarnAt) { 'Info' } elseif ($Count -ge $WarnAt) { 'Warn' } else { 'OK' }
    [pscustomobject]@{ Provider = $Cloud; Scope = $Scope; Check = $Check; Count = $Count; Status = $status; Detail = $Detail; Source = $Source }
  }
  $notConnected = {
    param($Cloud, $Detail)
    [pscustomobject]@{ Provider = $Cloud; Scope = ''; Check = 'Connection'; Count = $null; Status = 'NotConnected'; Detail = $Detail; Source = 'Live' }
  }

  $rows = @(
    if ($Provider -in 'Azure', 'Both') {
      if ($Mock) {
        & $finding 'Azure' 'sub-prod' 'Virtual machines' 38 $null 'Inventory' 'Mock'
        & $finding 'Azure' 'sub-prod' 'Unattached managed disks' 4 1 'disk-old-sql01-data, disk-tmp-02, +2 more' 'Mock'
        & $finding 'Azure' 'sub-prod' 'Unassociated public IPs' 0 1 '' 'Mock'
      }
      elseif (-not (Test-PlaybookCommand 'Get-AzContext', 'Get-AzVM', 'Get-AzDisk', 'Get-AzPublicIpAddress')) {
        & $notConnected 'Azure' 'Install-Module Az.Accounts, Az.Compute, Az.Network -Scope CurrentUser'
      }
      else {
        $ctx = Get-AzContext
        if (-not $ctx) {
          & $notConnected 'Azure' 'No Az context. Run Connect-AzAccount'
        }
        else {
          $sub = $ctx.Subscription.Name
          $vms = @(Get-AzVM)
          $disks = @(Get-AzDisk | Where-Object { $_.DiskState -eq 'Unattached' })
          $ips = @(Get-AzPublicIpAddress | Where-Object { -not $_.IpConfiguration -and -not $_.NatGateway })
          & $finding 'Azure' $sub 'Virtual machines' $vms.Count $null 'Inventory' 'Live'
          & $finding 'Azure' $sub 'Unattached managed disks' $disks.Count 1 (($disks | Select-Object -First 5 -ExpandProperty Name) -join ', ') 'Live'
          & $finding 'Azure' $sub 'Unassociated public IPs' $ips.Count 1 (($ips | Select-Object -First 5 -ExpandProperty Name) -join ', ') 'Live'
        }
      }
    }

    if ($Provider -in 'AWS', 'Both') {
      $scope = if ($Region) { $Region } else { 'default region' }
      if ($Mock) {
        & $finding 'AWS' 'us-east-1' 'EC2 instances' 12 $null 'Inventory' 'Mock'
        & $finding 'AWS' 'us-east-1' 'Unattached EBS volumes' 1 1 'vol-0a1b2c3d4e5f60718' 'Mock'
        & $finding 'AWS' 'us-east-1' "EBS snapshots > $SnapshotMaxAgeDays days" 7 1 'Oldest: 412 days' 'Mock'
      }
      elseif (-not (Test-PlaybookCommand 'Get-EC2Instance', 'Get-EC2Volume', 'Get-EC2Snapshot')) {
        & $notConnected 'AWS' 'Install-Module AWS.Tools.EC2 -Scope CurrentUser, then Set-AWSCredential'
      }
      else {
        $aws = @{ ErrorAction = 'Stop' }
        if ($Region) { $aws.Region = $Region }
        try {
          $instances = @((Get-EC2Instance @aws).Instances)
          $volumes = @(Get-EC2Volume @aws -Filter @{ Name = 'status'; Values = 'available' })
          $cutoff = (Get-Date).AddDays(-$SnapshotMaxAgeDays)
          $snaps = @(Get-EC2Snapshot @aws -OwnerId self | Where-Object { $_.StartTime -lt $cutoff })
          $oldest = if ($snaps) { 'Oldest: {0:N0} days' -f ((Get-Date) - ($snaps | Sort-Object StartTime | Select-Object -First 1).StartTime).TotalDays } else { '' }
          & $finding 'AWS' $scope 'EC2 instances' $instances.Count $null 'Inventory' 'Live'
          & $finding 'AWS' $scope 'Unattached EBS volumes' $volumes.Count 1 (($volumes | Select-Object -First 5 -ExpandProperty VolumeId) -join ', ') 'Live'
          & $finding 'AWS' $scope "EBS snapshots > $SnapshotMaxAgeDays days" $snaps.Count 1 $oldest 'Live'
        }
        catch {
          & $notConnected 'AWS' "AWS call failed (credentials/region?): $($_.Exception.Message)"
        }
      }
    }
  )

  Complete-PlaybookRun -OutDir $outDir -Name 'CloudBaseline' -Title 'Cloud Baseline' -Rows $rows `
    -Meta @{ Provider = $Provider; SnapshotMaxAgeDays = $SnapshotMaxAgeDays } -Mock:$Mock
}

# -----------------------------------------------------------------------------
# Microsoft 365 / Exchange Online
# -----------------------------------------------------------------------------
function Get-O365TenantHealth {
  <#
  .SYNOPSIS
    Exchange Online security posture checks.
  .DESCRIPTION
    Requires an Exchange Online session (Connect-ExchangeOnline, ExchangeOnlineManagement v3).
      - Unified audit log ingestion enabled
      - Modern authentication (OAuth2ClientProfileEnabled)
      - Automatic external forwarding allowed on the Default remote domain
      - Mailboxes forwarding to an external SMTP address (-IncludeForwardingRules)
    -IncludeSharingChecks also reads the SharePoint tenant sharing level (requires Connect-SPOService).
  .EXAMPLE
    Connect-ExchangeOnline; Get-O365TenantHealth -IncludeForwardingRules
  #>
  [CmdletBinding()]
  param(
    [switch] $IncludeForwardingRules,
    [switch] $IncludeSharingChecks,
    [switch] $Mock
  )
  $outDir = New-PlaybookOutputPath -FunctionName $MyInvocation.MyCommand.Name

  $check = {
    param($Area, $Name, $Status, $Detail, $Source)
    [pscustomobject]@{ Area = $Area; Check = $Name; Status = $Status; Detail = $Detail; Source = $Source }
  }

  $rows = @(
    if ($Mock) {
      & $check 'Exchange' 'Unified audit log' 'OK' 'Ingestion enabled' 'Mock'
      & $check 'Exchange' 'Modern authentication' 'OK' 'OAuth2ClientProfileEnabled = True' 'Mock'
      & $check 'Exchange' 'Auto-forward (Default remote domain)' 'Warn' 'AutoForwardEnabled = True' 'Mock'
      if ($IncludeForwardingRules) { & $check 'Exchange' 'Mailboxes forwarding externally' 'Fail' '2 mailbox(es): j.doe -> j.doe@gmail.com, +1 more' 'Mock' }
      if ($IncludeSharingChecks) { & $check 'SharePoint' 'External sharing level' 'Warn' 'ExternalUserAndGuestSharing (Anyone links)' 'Mock' }
    }
    elseif (-not (Test-PlaybookCommand 'Get-ConnectionInformation', 'Get-OrganizationConfig', 'Get-AdminAuditLogConfig', 'Get-RemoteDomain')) {
      & $check 'Exchange' 'Connection' 'NotConnected' 'Install-Module ExchangeOnlineManagement, then Connect-ExchangeOnline' 'Live'
    }
    elseif (-not (Get-ConnectionInformation)) {
      & $check 'Exchange' 'Connection' 'NotConnected' 'No Exchange Online session. Run Connect-ExchangeOnline' 'Live'
    }
    else {
      $audit = Get-AdminAuditLogConfig
      $status = if ($audit.UnifiedAuditLogIngestionEnabled) { 'OK' } else { 'Fail' }
      & $check 'Exchange' 'Unified audit log' $status "UnifiedAuditLogIngestionEnabled = $($audit.UnifiedAuditLogIngestionEnabled)" 'Live'

      $org = Get-OrganizationConfig
      $status = if ($org.OAuth2ClientProfileEnabled) { 'OK' } else { 'Fail' }
      & $check 'Exchange' 'Modern authentication' $status "OAuth2ClientProfileEnabled = $($org.OAuth2ClientProfileEnabled)" 'Live'

      $default = Get-RemoteDomain -Identity Default
      $status = if ($default.AutoForwardEnabled) { 'Warn' } else { 'OK' }
      & $check 'Exchange' 'Auto-forward (Default remote domain)' $status "AutoForwardEnabled = $($default.AutoForwardEnabled)" 'Live'

      if ($IncludeForwardingRules) {
        $fwd = @(Get-EXOMailbox -ResultSize Unlimited -Properties ForwardingSmtpAddress |
            Where-Object { $_.ForwardingSmtpAddress })
        $status = if ($fwd.Count) { 'Fail' } else { 'OK' }
        $detail = "$($fwd.Count) mailbox(es)"
        if ($fwd.Count) {
          $detail += ': ' + (($fwd | Select-Object -First 3 | ForEach-Object { "$($_.Alias) -> $($_.ForwardingSmtpAddress -replace '^smtp:', '')" }) -join ', ')
        }
        & $check 'Exchange' 'Mailboxes forwarding externally' $status $detail 'Live'
      }
    }

    if ($IncludeSharingChecks -and -not $Mock) {
      if (-not (Test-PlaybookCommand 'Get-SPOTenant')) {
        & $check 'SharePoint' 'External sharing level' 'NotConnected' 'Install-Module Microsoft.Online.SharePoint.PowerShell, then Connect-SPOService' 'Live'
      }
      else {
        try {
          $level = [string](Get-SPOTenant -ErrorAction Stop).SharingCapability
          $status = switch ($level) { 'Disabled' { 'OK' } 'ExistingExternalUserSharingOnly' { 'OK' } 'ExternalUserSharingOnly' { 'Warn' } default { 'Warn' } }
          & $check 'SharePoint' 'External sharing level' $status $level 'Live'
        }
        catch {
          & $check 'SharePoint' 'External sharing level' 'NotConnected' 'No SharePoint session. Run Connect-SPOService' 'Live'
        }
      }
    }
  )

  Complete-PlaybookRun -OutDir $outDir -Name 'O365TenantHealth' -Title 'Microsoft 365 Tenant Health' -Rows $rows `
    -Meta @{ Forwarding = [bool]$IncludeForwardingRules; Sharing = [bool]$IncludeSharingChecks } -Mock:$Mock
}

# -----------------------------------------------------------------------------
# Ticketing
# -----------------------------------------------------------------------------
function Publish-ReportToTicket {
  <#
  .SYNOPSIS
    Create or update a ticket and attach a report file (generic REST shim).
  .DESCRIPTION
    POSTs {title, body, project} to <BaseUrl>/tickets (or /tickets/<TicketId>) and uploads the file to
    <BaseUrl>/tickets/<id>/attachments as multipart form data. Adapt the routes to your ITSM's API.
    Configure via $env:TICKETS_BASE_URL, $env:TICKETS_API_TOKEN, $env:TICKETS_PROJECT.
  .EXAMPLE
    $r = Get-CloudBaseline; Publish-ReportToTicket -Title 'Weekly cloud hygiene' -Body 'See attached.' -FilePath $r.Html
  #>
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory)] [string] $Title,
    [Parameter(Mandatory)] [string] $Body,
    [Parameter(Mandatory)] [ValidateScript({ Test-Path $_ -PathType Leaf })] [string] $FilePath,
    [string] $TicketId
  )
  if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Publish-ReportToTicket requires PowerShell 7+ (multipart -Form upload).' }
  $cfg = $script:PlaybookConfig.Ticketing
  if (-not $cfg.BaseUrl -or -not $cfg.Token) { throw 'Set $env:TICKETS_BASE_URL and $env:TICKETS_API_TOKEN before importing the module.' }

  $base     = $cfg.BaseUrl.TrimEnd('/')
  $endpoint = if ($TicketId) { "$base/tickets/$TicketId" } else { "$base/tickets" }
  $headers  = @{ Authorization = "Bearer $($cfg.Token)" }

  if (-not $PSCmdlet.ShouldProcess($endpoint, "Publish '$Title' with $(Split-Path $FilePath -Leaf)")) { return }

  $payload = @{ title = $Title; body = $Body; project = $cfg.ProjectKey } | ConvertTo-Json
  $resp = Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body $payload -ContentType 'application/json'
  $tid = if ($TicketId) { $TicketId } else { $resp.id }
  if (-not $tid) { throw "Ticket API did not return an id (response: $($resp | ConvertTo-Json -Compress))" }

  $null = Invoke-RestMethod -Method Post -Uri "$base/tickets/$tid/attachments" -Headers $headers -Form @{ file = Get-Item -Path $FilePath }
  $tid
}

Export-ModuleMember -Function @(
  'New-PlaybookReport',
  'Invoke-WindowsUpdateBaseline',
  'Test-BackupRestoreReadiness',
  'Get-VMwareHealth',
  'Get-CloudBaseline',
  'Get-O365TenantHealth',
  'Publish-ReportToTicket'
)
