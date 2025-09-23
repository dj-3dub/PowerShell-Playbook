$pub = "./src/Public"

function Set-File ($name, $content) {
  $path = Join-Path $pub $name
  Set-Content -Path $path -Value $content -Encoding UTF8
  Write-Host "Updated $path"
}

# 1) Get-LocalAdminReport.ps1  (cross-platform; ADSI works only against Windows targets)
Set-File "Get-LocalAdminReport.ps1" @'
function Get-LocalAdminReport {
  [CmdletBinding()]
  param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    [string]$OutputPath = ".\reports",
    [string[]]$ApprovedMembers = @("Administrators","Domain Admins","Enterprise Admins")
  )

  function ConvertTo-ReportHtml([string]$Title,[string]$Fragment){ @"
<!doctype html><html><head><meta charset='utf-8'><title>$Title</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px}table{border-collapse:collapse;width:100%}
th,td{border:1px solid #ddd;padding:6px;text-align:left}th{background:#f4f4f4}</style></head>
<body><h1>$Title</h1>$Fragment</body></html>
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
  (ConvertTo-ReportHtml -Title "Local Admins Report" -Fragment $frag) | Out-File $file -Encoding UTF8
  Write-Information "Report: $file" -InformationAction Continue
}
'@

# 2) Get-CertificateExpiry.ps1 (Windows store providers; harmless to import)
Set-File "Get-CertificateExpiry.ps1" @'
function Get-CertificateExpiry {
  [CmdletBinding()]
  param(
    [ValidateSet("LocalMachine","CurrentUser")] [string]$StoreLocation="LocalMachine",
    [int]$ExpiresInDays=60,
    [string]$OutputPath=".\\reports"
  )

  function ConvertTo-ReportHtml([string]$Title,[string]$Fragment){ @"
<!doctype html><html><head><meta charset='utf-8'><title>$Title</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px}table{border-collapse:collapse;width:100%}
th,td{border:1px solid #ddd;padding:6px;text-align:left}th{background:#f4f4f4}</style></head>
<body><h1>$Title</h1>$Fragment</body></html>
"@ }

  $loc=if($StoreLocation -eq "LocalMachine"){"Cert:\\LocalMachine"}else{"Cert:\\CurrentUser"}
  $rows=Get-ChildItem "$loc\\" -Recurse -ErrorAction SilentlyContinue|
    Where-Object {$_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2]}|
    Select-Object PSParentPath,Subject,FriendlyName,NotAfter,
      @{n="DaysToExpire";e={[int]([datetime]$_.NotAfter-(Get-Date)).TotalDays}}|
    Sort-Object DaysToExpire

  $frag=$rows|ConvertTo-Html -Fragment
  New-Item -ItemType Directory -Force -Path $OutputPath|Out-Null
  $file=Join-Path $OutputPath ("CertExpiry-{0}.html"-f(Get-Date -Format "yyyyMMdd-HHmm"))
  (ConvertTo-ReportHtml -Title "Certificate Expiry (<= $ExpiresInDays days)" -Fragment $frag) | Out-File $file -Encoding UTF8
  Write-Information "Report: $file" -InformationAction Continue
}
'@

# 3) Get-DefenderStatus.ps1 (Windows-only at runtime)
Set-File "Get-DefenderStatus.ps1" @'
function Get-DefenderStatus {
  [CmdletBinding()] param([string]$OutputPath=".\\reports")
  if (-not $IsWindows) { return }

  function ConvertTo-ReportHtml([string]$Title,[string]$Fragment){ @"
<!doctype html><html><head><meta charset='utf-8'><title>$Title</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px}table{border-collapse:collapse;width:100%}
th,td{border:1px solid #ddd;padding:6px;text-align:left}th{background:#f4f4f4}</style></head>
<body><h1>$Title</h1>$Fragment</body></html>
"@ }

  try{$mp=Get-MpComputerStatus}catch{$mp=$null}
  if(-not $mp){ return }

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
  (ConvertTo-ReportHtml -Title "Windows Defender Status" -Fragment $frag) | Out-File $file -Encoding UTF8
  Write-Information "Report: $file" -InformationAction Continue
}
'@

# 4) Invoke-WinGetBaseline.ps1 (Windows-only; SupportsShouldProcess)
Set-File "Invoke-WinGetBaseline.ps1" @'
function Invoke-WinGetBaseline {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [string[]]$Packages=@("Microsoft.WindowsTerminal","7zip.7zip","Git.Git"),
    [switch]$Apply
  )
  if (-not $IsWindows) { return }

  $winget=Get-Command winget -ErrorAction SilentlyContinue
  if(-not $winget){ return }

  foreach($pkg in $Packages){
    $installed=winget list --id $pkg 2>$null
    if($installed){
      Write-Information "[OK] $pkg already installed" -InformationAction Continue
    } else {
      if($Apply){
        if ($PSCmdlet.ShouldProcess($pkg,"winget install")) {
          winget install --id $pkg --accept-source-agreements --accept-package-agreements | Out-Host
        }
      } else {
        Write-Information "[AUDIT] Would install $pkg (use -Apply to install)" -InformationAction Continue
      }
    }
  }
}
'@

# 5) Collect-SupportBundle.ps1 (Windows-only; no work at import)
Set-File "Collect-SupportBundle.ps1" @'
function Collect-SupportBundle {
  [CmdletBinding()]
  param([string]$OutputPath=".\\reports",[int]$Hours=24)
  if (-not $IsWindows) { return }

  $root=Join-Path $OutputPath ("SupportBundle-{0}"-f(Get-Date -Format "yyyyMMdd-HHmm"))
  New-Item -ItemType Directory -Force -Path $root|Out-Null

  Get-ComputerInfo | Out-File (Join-Path $root "computerinfo.txt") -ErrorAction SilentlyContinue
  ipconfig /all > (Join-Path $root "ipconfig.txt") 2>&1

  $logs="System","Application"
  foreach($l in $logs){
    wevtutil epl "$l" (Join-Path $root ("$l.evtx")) /q:"*[System[TimeCreated[timediff(@SystemTime) <= $(($Hours*60*60*1000))]]]" 2>$null
  }

  $zip="$root.zip"
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::CreateFromDirectory($root,$zip)
  Write-Information "Support bundle: $zip" -InformationAction Continue
}
'@

Write-Host "`nFiles rewritten as functions. Re-import the module and rerun tests." -ForegroundColor Cyan

