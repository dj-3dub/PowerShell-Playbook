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
