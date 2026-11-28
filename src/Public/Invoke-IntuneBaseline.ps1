function Invoke-IntuneBaseline {
    <#
    .SYNOPSIS
    Reports Intune compliance for Windows devices and, with -Enforce, triggers a sync on non-compliant ones.

    .DESCRIPTION
    Live mode reads Windows managed devices from Microsoft Graph and reports their compliance state and
    last check-in. With -Enforce, each non-compliant device is sent a "sync device" action so it re-evaluates
    and re-applies its assigned policies (each sync goes through ShouldProcess, so -WhatIf/-Confirm work).

    Graph permissions: DeviceManagementManagedDevices.Read.All, plus
    DeviceManagementManagedDevices.PrivilegedOperations.All for -Enforce.

    When the environment config (src/config/<Environment>.json) sets UseMockData, sample devices are used
    and -Enforce only reports what it would do.

    .PARAMETER Environment
    Config to load: Dev, Test or Prod.

    .PARAMETER StaleDays
    Devices that have not checked in for this many days are flagged Stale. Default 7.

    .PARAMETER Enforce
    Trigger an Intune sync for each non-compliant device.

    .PARAMETER OutputPath
    Folder for the CSV and HTML report. Default ./reports.

    .EXAMPLE
    Connect-MgGraph -Scopes DeviceManagementManagedDevices.Read.All
    Invoke-IntuneBaseline -Environment Prod

    .EXAMPLE
    Invoke-IntuneBaseline -Environment Prod -Enforce -WhatIf

    .OUTPUTS
    One object per device; the HTML report path is written to the information stream.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [ValidateSet('Dev', 'Test', 'Prod')]
        [string]$Environment = 'Dev',

        [ValidateRange(1, 365)]
        [int]$StaleDays = 7,

        [switch]$Enforce,

        [string]$OutputPath = './reports'
    )

    $cfg = Get-PlaybookConfig -Environment $Environment
    $mock = [bool]$cfg.UseMockData
    Write-ToolkitLog -Level Info -Message 'Intune baseline start' -Data @{ Env = $Environment; Enforce = $Enforce.IsPresent; Mock = $mock }

    $now = Get-Date
    if ($mock) {
        $devices = @(
            [pscustomobject]@{ Id = 'mock-1'; DeviceName = 'PC-001'; ComplianceState = 'compliant';    LastSyncDateTime = $now.AddHours(-3); OSVersion = '10.0.26100.2605' }
            [pscustomobject]@{ Id = 'mock-2'; DeviceName = 'PC-002'; ComplianceState = 'noncompliant'; LastSyncDateTime = $now.AddDays(-1);  OSVersion = '10.0.22631.4460' }
            [pscustomobject]@{ Id = 'mock-3'; DeviceName = 'PC-003'; ComplianceState = 'compliant';    LastSyncDateTime = $now.AddDays(-12); OSVersion = '10.0.22631.4460' }
        )
    }
    else {
        foreach ($cmd in 'Get-MgContext', 'Get-MgDeviceManagementManagedDevice') {
            if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
                throw 'Microsoft.Graph.DeviceManagement is not installed. Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser'
            }
        }
        if (-not (Get-MgContext)) {
            throw 'No Microsoft Graph session. Run Connect-MgGraph -Scopes DeviceManagementManagedDevices.Read.All'
        }
        $devices = @(Invoke-WithRetry { Get-MgDeviceManagementManagedDevice -All -Filter "operatingSystem eq 'Windows'" })
    }

    $results = foreach ($d in $devices) {
        $daysSinceSync = if ($d.LastSyncDateTime) { [math]::Round(($now - $d.LastSyncDateTime).TotalDays, 1) } else { $null }
        $status = if ([string]$d.ComplianceState -eq 'noncompliant') { 'NonCompliant' }
                  elseif ($null -eq $daysSinceSync -or $daysSinceSync -gt $StaleDays) { 'Stale' }
                  elseif ([string]$d.ComplianceState -eq 'compliant') { 'Compliant' }
                  else { [string]$d.ComplianceState }

        $action = 'None'
        if ($Enforce -and $status -eq 'NonCompliant') {
            if ($PSCmdlet.ShouldProcess($d.DeviceName, 'Trigger Intune device sync')) {
                if ($mock) {
                    $action = 'SyncRequested (mock)'
                }
                else {
                    try {
                        Invoke-WithRetry { Sync-MgDeviceManagementManagedDevice -ManagedDeviceId $d.Id -ErrorAction Stop }
                        $action = 'SyncRequested'
                    }
                    catch {
                        $action = "SyncFailed: $($_.Exception.Message)"
                        Write-ToolkitLog -Level Warn -Message "Sync failed for $($d.DeviceName)" -Data @{ Error = $_.Exception.Message }
                    }
                }
            }
            else {
                $action = 'SyncSkipped (WhatIf)'
            }
        }

        [pscustomobject]@{
            DeviceName      = $d.DeviceName
            Status          = $status
            ComplianceState = [string]$d.ComplianceState
            DaysSinceSync   = $daysSinceSync
            OSVersion       = $d.OSVersion
            Action          = $action
        }
    }
    $results = @($results)

    # The report is read-only output; write it even under -WhatIf (that is when the plan matters most).
    New-Item -ItemType Directory -Force -Path $OutputPath -WhatIf:$false | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $title = "Intune Baseline ($Environment)"
    if ($mock) { $title += ' [MOCK]' }
    $results | Export-Csv -Path (Join-Path $OutputPath "IntuneBaseline-$stamp.csv") -NoTypeInformation -Encoding UTF8 -WhatIf:$false
    $html = Join-Path $OutputPath "IntuneBaseline-$stamp.html"
    ConvertTo-ReportHtml -Title $title -Data $results | Out-File -FilePath $html -Encoding UTF8 -WhatIf:$false
    Write-Information "Report: $html"

    Write-ToolkitLog -Level Info -Message 'Intune baseline complete' -Data @{
        Env = $Environment; Devices = $results.Count; NonCompliant = @($results | Where-Object Status -eq 'NonCompliant').Count
    }
    $results
}
