[CmdletBinding()]
param(
  [string]$SrcPublic = "./src/Public",
  [string]$Manifest   = "./src/EnterpriseOpsToolkit.psd1"
)

# ---------------- helpers ----------------
function Write-ScriptFile {
  param([Parameter(Mandatory)] [string]$Name, [Parameter(Mandatory)] [string]$Content)
  $path = Join-Path $SrcPublic $Name
  New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
  Set-Content -Path $path -Value $Content -Encoding UTF8
  Write-Host "Created: $path" -ForegroundColor Green
}

function Merge-FunctionsToExport {
  param([string]$ManifestPath, [string[]]$Add)
  if (-not (Test-Path $ManifestPath)) { throw "Manifest not found: $ManifestPath" }

  $data = Import-PowerShellDataFile -Path $ManifestPath

  # If FunctionsToExport is '*', keep it (already exports everything)
  if ($data.FunctionsToExport -eq '*' -or ($data.FunctionsToExport -is [string] -and $data.FunctionsToExport.Trim() -eq '*')) {
    Write-Host "Manifest exports '*' already; no update needed." -ForegroundColor Yellow
    return
  }

  # Normalize to array
  $current = @()
  if ($null -ne $data.FunctionsToExport) {
    if ($data.FunctionsToExport -is [string]) { $current = @($data.FunctionsToExport) }
    else { $current = @($data.FunctionsToExport) }
  }

  $merged = ($current + $Add) | Where-Object { $_ -and $_.Trim() } | Sort-Object -Unique

  # Use Update-ModuleManifest to update only FunctionsToExport, preserving others
  Update-ModuleManifest -Path $ManifestPath -FunctionsToExport $merged
  Write-Host "Updated FunctionsToExport in manifest." -ForegroundColor Green
}

# ------------- begin generation -------------
New-Item -ItemType Directory -Force -Path $SrcPublic | Out-Null

# 1) Local Admin Report
Write-ScriptFile "Get-LocalAdminReport.ps1" @'
[CmdletBinding()]
param(
  [string[]]$ComputerName = @($env:COMPUTERNAME),
  [string]$OutputPath = ".\reports",
  [string[]]$ApprovedMembers = @("Administrators","Domain Admins","Enterprise Admins")
)
function New-ReportHtml($title,$frag){ @"
<!doctype html><html><head><meta charset='utf-8'><title>$title</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px}table{border-collapse:collapse;width:100%}
th,td{border:1px solid #ddd;padding:6px;text-align:left}th{background:#f4f4f4}</style></head>
<body><h1>$title</h1>$frag</body></html>
"@ }
$results = foreach($c in $ComputerName){
  try{
    $grp = [ADSI]"WinNT://$c/Administrators,group"
    $grp.psbase.Invoke("Members") | ForEach-Object {
      $path=$_.GetType().InvokeMember("ADsPath","GetProperty",$null,$_,$null)
      $n=$path -replace "^.+?=([^/]+).+$","$1"
      [pscustomobject]@{Computer=$c;Member=$n;IsApproved=$ApprovedMembers -contains $n}
    }
  }catch{
    [pscustomobject]@{Computer=$c;Member="(error)";IsApproved=$false;Error=$_.Exception.Message}
  }
}
$frag=$results|ConvertTo-Html -Property Computer,Member,IsApproved,Error -Fragment
New-Item -ItemType Directory -Force -Path $OutputPath|Out-Null
$file=Join-Path $OutputPath ("LocalAdmins-{0}.html"-f(Get-Date -Format "yyyyMMdd-HHmm"))
(New-ReportHtml -title "Local Admins Report" -frag $frag)|Out-File $file -Encoding UTF8
Write-Host "Report: $file"
'@

# 2) Certificate Expiry
Write-ScriptFile "Get-CertificateExpiry.ps1" @'
[CmdletBinding()]
param(
  [ValidateSet("LocalMachine","CurrentUser")] [string]$StoreLocation="LocalMachine",
  [int]$ExpiresInDays=60,
  [string]$OutputPath=".\\reports"
)
function New-ReportHtml($title,$frag){ @"
<!doctype html><html><head><meta charset='utf-8'><title>$title</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px}table{border-collapse:collapse;width:100%}
th,td{border:1px solid #ddd;padding:6px;text-align:left}th{background:#f4f4f4}</style></head>
<body><h1>$title</h1>$frag</body></html>
"@ }
$deadline=(Get-Date).AddDays($ExpiresInDays)
$loc=if($StoreLocation -eq "LocalMachine"){"Cert:\\LocalMachine"}else{"Cert:\\CurrentUser"}
$rows=Get-ChildItem "$loc\\" -Recurse -ErrorAction SilentlyContinue|
 Where-Object {$_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2]}|
 Select-Object PSParentPath,Subject,FriendlyName,NotAfter,@{n="DaysToExpire";e={[int]([datetime]$_.NotAfter-(Get-Date)).TotalDays}}|
 Sort-Object DaysToExpire
$frag=$rows|ConvertTo-Html -Fragment
New-Item -ItemType Directory -Force -Path $OutputPath|Out-Null
$file=Join-Path $OutputPath ("CertExpiry-{0}.html"-f(Get-Date -Format "yyyyMMdd-HHmm"))
(New-ReportHtml -title "Certificate Expiry (<= $ExpiresInDays days)" -frag $frag)|Out-File $file -Encoding UTF8
Write-Host "Report: $file"
'@

# 3) Defender Status (Windows-only at runtime)
Write-ScriptFile "Get-DefenderStatus.ps1" @'
[CmdletBinding()]param([string]$OutputPath=".\\reports")
function New-ReportHtml($title,$frag){ @"
<!doctype html><html><head><meta charset='utf-8'><title>$title</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px}table{border-collapse:collapse;width:100%}
th,td{border:1px solid #ddd;padding:6px;text-align:left}th{background:#f4f4f4}</style></head>
<body><h1>$title</h1>$frag</body></html>
"@ }
try{$mp=Get-MpComputerStatus}catch{$mp=$null}
if(-not $mp){Write-Warning "Windows Defender not found or cmdlets unavailable.";return}
$sum=[pscustomobject]@{
 AMServiceEnabled=$mp.AMServiceEnabled
 AntivirusEnabled=$mp.AntivirusEnabled
 RealTimeProtection=$mp.RealTimeProtectionEnabled
 TamperProtection=$mp.IsTamperProtected
 EngineVersion=$mp.AMEngineVersion
 AVSignatureVersion=$mp.AntivirusSignatureVersion
 SignatureAgeHours=[int]((Get-Date)-$mp.AntivirusSignatureLastUpdated).TotalHours
}
$frag=$sum|ConvertTo-Html -Fragment
New-Item -ItemType Directory -Force -Path $OutputPath|Out-Null
$file=Join-Path $OutputPath ("DefenderStatus-{0}.html"-f(Get-Date -Format "yyyyMMdd-HHmm"))
(New-ReportHtml -title "Windows Defender Status" -frag $frag)|Out-File $file -Encoding UTF8
Write-Host "Report: $file"
'@

# 4) WinGet Baseline (Windows-only at runtime)
Write-ScriptFile "Invoke-WinGetBaseline.ps1" @'
[CmdletBinding(SupportsShouldProcess)]
param([string[]]$Packages=@("Microsoft.WindowsTerminal","7zip.7zip","Git.Git"),[switch]$Apply)
$winget=Get-Command winget -ErrorAction SilentlyContinue
if(-not $winget){Write-Warning "winget not found. Skipping.";return}
foreach($pkg in $Packages){
 $installed=winget list --id $pkg 2>$null
 if($installed){Write-Host "[OK] $pkg already installed"}else{
  if($Apply -and $PSCmdlet.ShouldProcess($pkg,"winget install")){
   winget install --id $pkg --accept-source-agreements --accept-package-agreements|Out-Host
  }else{Write-Host "[AUDIT] Would install $pkg (use -Apply to install)"}
 }}
'@

# 5) Support Bundle (Windows-only at runtime)
Write-ScriptFile "Collect-SupportBundle.ps1" @'
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
'@

# ----- Update manifest to export new functions -----
$newFunctions = @(
  'Get-LocalAdminReport',
  'Get-CertificateExpiry',
  'Get-DefenderStatus',
  'Invoke-WinGetBaseline',
  'Collect-SupportBundle'
)

try {
  Merge-FunctionsToExport -ManifestPath $Manifest -Add $newFunctions
} catch {
  Write-Warning "Manifest update failed: $($_.Exception.Message)"
  Write-Host "Please add these to FunctionsToExport manually:" -ForegroundColor Yellow
  $newFunctions | ForEach-Object { Write-Host "  - $_" }
}

Write-Host "`nDone. New scripts created and manifest checked." -ForegroundColor Cyan

