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
