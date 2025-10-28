<#
.SYNOPSIS
  One-shot triage for "my PC is slow" cases. Generates a compact HTML + TXT report.
.DESCRIPTION
  Collects system health signals (CPU, RAM, disk, processes, startup apps, event errors, update state)
  and writes a support bundle to a timestamped folder.
.PARAMETER OutputPath
  Folder to write the bundle into. Defaults to .\SupportBundles\<hostname>-<timestamp>\
.PARAMETER Hours
  Event log lookback window. Defaults to 2 hours.
.EXAMPLE
  .\Diagnose-SlowPC.ps1 -Verbose
.NOTES
  Run as administrator for full fidelity. No external modules required.
#>
[CmdletBinding()]
param(
  [string]$OutputPath,
  [int]$Hours = 2
)

function Ensure-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
  if (-not $isAdmin) { Write-Warning "This script should be run as Administrator for best results." }
}

function New-BundleFolder {
  $hostName = $env:COMPUTERNAME
  $ts = Get-Date -Format "yyyyMMdd-HHmmss"
  if (-not $OutputPath) {
    $OutputPath = Join-Path -Path (Join-Path -Path (Get-Location) -ChildPath "SupportBundles") -ChildPath "$hostName-$ts"
  }
  New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
  return $OutputPath
}

function Collect-QuickFacts {
@"
Hostname       : $env:COMPUTERNAME
User           : $env:USERNAME
OS             : $((Get-CimInstance Win32_OperatingSystem).Caption) $((Get-CimInstance Win32_OperatingSystem).Version)
LastBoot       : $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)
Uptime         : $([TimeSpan]::FromSeconds((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToFileTimeUtc() - [datetime]::UtcNow.ToFileTimeUtc()).Duration())
CPU            : $((Get-CimInstance Win32_Processor).Name -join ', ')
Cores/Logical  : $((Get-CimInstance Win32_Processor).NumberOfCores -join ', ')/$((Get-CimInstance Win32_Processor).NumberOfLogicalProcessors -join ', ')
RAM (GB)       : {0:N2}
System Drive   : $((Get-PSDrive -Name C).Free/1GB -as [double]) GB free of $((Get-PSDrive -Name C).Used/1GB + (Get-PSDrive -Name C).Free/1GB) GB
Power Plan     : $((powercfg /getactivescheme) 2>$null)
"@ -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)
}

function Collect-TopProcesses {
  Get-Process | Sort-Object CPU -Descending | Select-Object -First 20 `
    @{n='Name';e={$_.Name}},
    @{n='Id';e={$_.Id}},
    @{n='CPU(s)';e={[math]::Round($_.CPU,2)}},
    @{n='WorkingSet(MB)';e={[math]::Round($_.WorkingSet64/1MB,2)}},
    @{n='StartTime';e={$_.StartTime}} | Format-Table -AutoSize | Out-String
}

function Collect-Startup {
  try {
    Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location | Format-Table -AutoSize | Out-String
  } catch {
    "Startup inspection failed: $($_.Exception.Message)"
  }
}

function Collect-EventErrors {
  $since = (Get-Date).AddHours(-$Hours)
  $filters = @(
    @{ LogName='System'; Level=2; StartTime=$since },
    @{ LogName='Application'; Level=2; StartTime=$since }
  )
  $lines = foreach ($f in $filters) {
    Get-WinEvent -FilterHashtable $f -ErrorAction SilentlyContinue |
      Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message |
      Format-List | Out-String
  }
  return $lines -join "`r`n"
}

function Collect-Updates {
  try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and Type='Software'")
    "Pending Updates: {0}`r`n" -f $result.Updates.Count
  } catch {
    "Windows Update quick scan unavailable (COM blocked)."
  }
}

function Collect-Disk {
  try {
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
      Select-Object DeviceID, @{n='Size(GB)';e={[math]::Round($_.Size/1GB,1)}}, @{n='Free(GB)';e={[math]::Round($_.FreeSpace/1GB,1)}}, @{n='Free(%)';e={[math]::Round(($_.FreeSpace/$_.Size)*100,1)}} |
      Format-Table -AutoSize | Out-String
  } catch { "Disk inspection failed: $($_.Exception.Message)" }
}

Ensure-Admin
$bundle = New-BundleFolder
$txt = Join-Path $bundle "diagnostics.txt"
$html = Join-Path $bundle "diagnostics.html"

$sections = @{
  "Quick Facts"      = Collect-QuickFacts
  "Disk Utilization" = Collect-Disk
  "Top Processes"    = Collect-TopProcesses
  "Startup Items"    = Collect-Startup
  "Recent Critical Errors" = Collect-EventErrors
  "Windows Update"   = Collect-Updates
  "Network"          = (ipconfig /all | Out-String)
}

# Write TXT
"==== PC DIAGNOSTICS ($(Get-Date)) ====" | Out-File -FilePath $txt -Encoding UTF8
foreach($k in $sections.Keys){
  "`r`n---- $k ----`r`n" | Out-File -FilePath $txt -Append -Encoding UTF8
  $sections[$k] | Out-File -FilePath $txt -Append -Encoding UTF8
}

# Simple HTML render
$body = foreach($k in $sections.Keys){
  "<h2>$k</h2><pre>{0}</pre>" -f [System.Web.HttpUtility]::HtmlEncode(($sections[$k] -join "`r`n"))
}
@"
<!DOCTYPE html>
<html>
<head><meta charset='utf-8'><title>PC Diagnostics - $env:COMPUTERNAME</title>
<style>body{font-family:Segoe UI,Arial;max-width:1100px;margin:24px;} pre{background:#111;color:#f2f2f2;padding:12px;border-radius:8px;overflow:auto;}</style>
</head>
<body>
<h1>PC Diagnostics - $env:COMPUTERNAME</h1>
<p>Generated: $(Get-Date)</p>
$($body -join "`n")
</body></html>
"@ | Out-File -FilePath $html -Encoding UTF8

# Compress bundle
$zip = Join-Path $bundle "SupportBundle-$($env:COMPUTERNAME).zip"
Compress-Archive -Path (Join-Path $bundle "*") -DestinationPath $zip -Force

Write-Host "Bundle written to: $bundle"
Write-Host "ZIP: $zip"
