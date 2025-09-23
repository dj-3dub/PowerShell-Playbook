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

