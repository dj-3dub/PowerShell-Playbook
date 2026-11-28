function Export-SupportBundle {
  <#
    .SYNOPSIS
    Collects common Windows troubleshooting artifacts into a timestamped folder and ZIP, plus an HTML summary.

    .DESCRIPTION
    Gathers: computer info, services, top processes by CPU, hotfixes, ipconfig/route/netstat, and
    Error/Critical events from the System and Application logs for the last -Hours (as CSV).
    Windows only; on other platforms it warns and returns $null.

    For the helpdesk flow (ticket ID in the name, Teams logs, connectivity tests) use
    scripts/helpdesk/Export-HelpdeskLogs.ps1 instead.

    .PARAMETER OutputPath
    Folder to place the bundle folder, ZIP, and HTML summary. Default ./reports.

    .PARAMETER Hours
    Event log lookback window. Default 24.

    .EXAMPLE
    Export-SupportBundle -OutputPath .\reports -Hours 48

    .OUTPUTS
    Path to the HTML summary.
    #>
  [CmdletBinding(SupportsShouldProcess)]
  [Alias('Collect-SupportBundle')]
  param(
    [string]$OutputPath = './reports',
    [ValidateRange(1, 720)] [int]$Hours = 24
  )

  # Relies on Get-Service, CIM/WMI, ipconfig and the Windows event log.
  # ($IsWindows is undefined on Windows PowerShell 5.1, which only runs on Windows.)
  if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
    Write-Warning 'Export-SupportBundle requires Windows; skipping.'
    return $null
  }

  New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
  $stamp     = Get-Date -Format 'yyyyMMdd-HHmm'
  $bundleDir = Join-Path $OutputPath "SupportBundle-$env:COMPUTERNAME-$stamp"
  $zipPath   = "$bundleDir.zip"
  $htmlPath  = "$bundleDir.html"

  if (-not $PSCmdlet.ShouldProcess($bundleDir, 'Create support bundle')) { return $null }
  New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null

  # Each collector writes one file; a failure is recorded in that file instead of aborting the bundle.
  $collect = {
    param([string]$File, [scriptblock]$Action)
    $target = Join-Path $bundleDir $File
    try { & $Action $target }
    catch { "Collection failed: $($_.Exception.Message)" | Out-File -Encoding UTF8 $target }
  }

  & $collect 'ComputerInfo.txt' { param($t) Get-ComputerInfo | Out-File -Encoding UTF8 $t }
  & $collect 'Services.txt'     { param($t) Get-Service | Sort-Object Status, DisplayName | Format-Table -AutoSize | Out-String -Width 250 | Out-File -Encoding UTF8 $t }
  & $collect 'TopProcesses.txt' { param($t) Get-Process | Sort-Object CPU -Descending | Select-Object -First 50 Name, Id, CPU, WorkingSet64, StartTime | Format-Table -AutoSize | Out-String -Width 250 | Out-File -Encoding UTF8 $t }
  & $collect 'HotFix.txt'       { param($t) Get-HotFix | Sort-Object InstalledOn | Format-Table -AutoSize | Out-String -Width 250 | Out-File -Encoding UTF8 $t }
  & $collect 'ipconfig.txt'     { param($t) ipconfig /all | Out-File -Encoding UTF8 $t }
  & $collect 'routes.txt'       { param($t) route print | Out-File -Encoding UTF8 $t }
  & $collect 'netstat.txt'      { param($t) netstat -ano | Out-File -Encoding UTF8 $t }

  $since = (Get-Date).AddHours(-$Hours)
  foreach ($log in 'System', 'Application') {
    & $collect "Events-$log-Errors-${Hours}h.csv" {
      param($t)
      # Level 1 = Critical, 2 = Error
      Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1, 2; StartTime = $since } -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Export-Csv -Path $t -NoTypeInformation -Encoding UTF8
    }
  }

  Compress-Archive -Path (Join-Path $bundleDir '*') -DestinationPath $zipPath -Force

  $os = Get-CimInstance Win32_OperatingSystem
  $facts = [ordered]@{
    Computer    = $env:COMPUTERNAME
    User        = $env:USERNAME
    OS          = "$($os.Caption) ($($os.Version))"
    LastBoot    = $os.LastBootUpTime
    EventWindow = "$Hours h"
    Zip         = Split-Path $zipPath -Leaf
  }
  $files = @(Get-ChildItem -Path $bundleDir -File | Select-Object Name, Length, LastWriteTime)

  ConvertTo-ReportHtml -Title "Support Bundle: $env:COMPUTERNAME" -Data $files -Meta $facts |
    Out-File -Encoding UTF8 $htmlPath

  Write-Verbose "Bundle: $bundleDir"
  Write-Verbose "Zip:    $zipPath"
  Write-Verbose "Report: $htmlPath"
  $htmlPath
}
