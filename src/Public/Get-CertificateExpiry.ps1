function Get-CertificateExpiry {
  <#
  .SYNOPSIS
  Reports certificates in the local machine or user store that expire within -ExpiresInDays (including already expired).

  .PARAMETER StoreLocation
  LocalMachine (default) or CurrentUser.

  .PARAMETER ExpiresInDays
  Include certificates expiring within this many days. Default 60.

  .PARAMETER OutputPath
  Folder for the HTML report. Default ./reports.

  .EXAMPLE
  Get-CertificateExpiry -ExpiresInDays 30

  .OUTPUTS
  The certificates found; the report path is written to the information stream.
  #>
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
    Where-Object { $_.DaysToExpire -le $ExpiresInDays } |
    Sort-Object DaysToExpire

  $frag=$rows|ConvertTo-Html -Fragment
  New-Item -ItemType Directory -Force -Path $OutputPath|Out-Null
  $file=Join-Path $OutputPath ("CertExpiry-{0}.html"-f(Get-Date -Format "yyyyMMdd-HHmm"))
  (ConvertTo-ReportHtml -Title "Certificate Expiry (<= $ExpiresInDays days)" -Fragment $frag) | Out-File $file -Encoding UTF8
  Write-Information "Report: $file" -InformationAction Continue
  $rows
}

