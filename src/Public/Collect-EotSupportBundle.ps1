[CmdletBinding()]
param([string]$OutputPath=".\\reports",[int]$Hours=24)
$root=Join-Path $OutputPath ("SupportBundle-{0}"-f(Get-Date -Format "yyyyMMdd-HHmm"))
New-Item -ItemType Directory -Force -Path $root|Out-Null
# Some commands are Windows-specific; this script is intended to run on Windows.
Get-ComputerInfo | Out-File (Join-Path $root "computerinfo.txt") -ErrorAction SilentlyContinue
ipconfig /all > (Join-Path $root "ipconfig.txt") 2>&1
$logs="System","Application"
foreach($l in $logs){
  wevtutil epl "$l" (Join-Path $root ("$l.evtx")) /q:"*[System[TimeCreated[timediff(@SystemTime) <= $(($Hours*60*60*1000))]]]" 2>$null
}
$zip="$root.zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($root,$zip)
Write-Host "Support bundle: $zip"
