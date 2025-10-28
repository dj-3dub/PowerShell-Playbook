<#
.SYNOPSIS
  Collects common diagnostics into a zipped support bundle.
.EXAMPLE
  .\Collect-SupportBundle.ps1 -Verbose
#>
[CmdletBinding()]
param(
  [string]$OutputRoot = ".\SupportBundles"
)
$hostName = $env:COMPUTERNAME
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$bundle = Join-Path $OutputRoot "$hostName-$ts"
New-Item -ItemType Directory -Path $bundle -Force | Out-Null

$log = Join-Path $bundle "bundle.log"
function Log($m){ ("[{0}] {1}" -f (Get-Date), $m) | Tee-Object -FilePath $log -Append }

Log "Collecting msinfo32..."
Start-Process -FilePath "msinfo32.exe" -ArgumentList "/nfo `"$bundle\msinfo32.nfo`"" -Wait -NoNewWindow

Log "Collecting dxdiag..."
Start-Process -FilePath "dxdiag.exe" -ArgumentList "/t `"$bundle\dxdiag.txt`"" -Wait -NoNewWindow

Log "Capturing ipconfig /all ..."
ipconfig /all | Out-File -FilePath (Join-Path $bundle "ipconfig.txt") -Encoding UTF8

Log "Capturing routes..."
route print | Out-File -FilePath (Join-Path $bundle "routes.txt") -Encoding UTF8

Log "Capturing services snapshot..."
Get-Service | Sort-Object Status, Name | Format-Table -AutoSize | Out-File (Join-Path $bundle "services.txt")

Log "Capturing running processes..."
Get-Process | Sort-Object CPU -Descending | Select-Object -First 50 | Format-Table -AutoSize | Out-File (Join-Path $bundle "processes.txt")

Log "Exporting System/Application errors (24h)..."
$since = (Get-Date).AddHours(-24)
Get-WinEvent -FilterHashtable @{ LogName='System'; Level=2; StartTime=$since } -ErrorAction SilentlyContinue |
  Export-Csv (Join-Path $bundle "system-errors-24h.csv") -NoTypeInformation
Get-WinEvent -FilterHashtable @{ LogName='Application'; Level=2; StartTime=$since } -ErrorAction SilentlyContinue |
  Export-Csv (Join-Path $bundle "application-errors-24h.csv") -NoTypeInformation

Log "Creating ZIP..."
$zipPath = Join-Path $bundle "SupportBundle-$hostName.zip"
Compress-Archive -Path (Join-Path $bundle "*") -DestinationPath $zipPath -Force
Log "Done. ZIP: $zipPath"
Write-Host "Bundle created at $bundle"
