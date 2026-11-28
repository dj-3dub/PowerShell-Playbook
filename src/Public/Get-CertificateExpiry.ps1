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

  $loc=if($StoreLocation -eq "LocalMachine"){"Cert:\\LocalMachine"}else{"Cert:\\CurrentUser"}
  $rows=Get-ChildItem "$loc\\" -Recurse -ErrorAction SilentlyContinue|
    Where-Object {$_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2]}|
    Select-Object PSParentPath,Subject,FriendlyName,NotAfter,
      @{n="DaysToExpire";e={[int]([datetime]$_.NotAfter-(Get-Date)).TotalDays}}|
    Where-Object { $_.DaysToExpire -le $ExpiresInDays } |
    Sort-Object DaysToExpire |
    Select-Object @{n="Status";e={ if ($_.DaysToExpire -lt 0) { "Expired" } elseif ($_.DaysToExpire -le 14) { "Expiring" } else { "OK" } }}, *

  New-Item -ItemType Directory -Force -Path $OutputPath|Out-Null
  $file=Join-Path $OutputPath ("CertExpiry-{0}.html"-f(Get-Date -Format "yyyyMMdd-HHmm"))
  ConvertTo-ReportHtml -Title "Certificate Expiry (within $ExpiresInDays days)" -Data @($rows) -Meta ([ordered]@{ Store = $StoreLocation; Window = "$ExpiresInDays days" }) |
    Out-File $file -Encoding UTF8
  Write-Information "Report: $file" -InformationAction Continue
  $rows
}

