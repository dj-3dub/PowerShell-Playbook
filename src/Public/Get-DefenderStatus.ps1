function Get-DefenderStatus {
  <#
  .SYNOPSIS
  Reports Microsoft Defender Antivirus health on the local machine (service, real-time and tamper protection, signature age).

  .DESCRIPTION
  Windows only; returns nothing on other platforms or when Defender is not the active AV.

  .PARAMETER OutputPath
  Folder for the HTML report. Default ./reports.

  .EXAMPLE
  Get-DefenderStatus -OutputPath .\reports
  #>
  [CmdletBinding()] param([string]$OutputPath=".\\reports")
  # $IsWindows does not exist on Windows PowerShell 5.1 (which is always Windows).
  if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { return }

  try{$mp=Get-MpComputerStatus}catch{$mp=$null}
  if(-not $mp){ return }

  $sigAge=[int]((Get-Date)-$mp.AntivirusSignatureLastUpdated).TotalHours
  $status=if (-not $mp.AntivirusEnabled -or -not $mp.RealTimeProtectionEnabled) { "Fail" } elseif ($sigAge -gt 48) { "Warn" } else { "OK" }
  $sum=[pscustomobject]@{
    Status=$status
    AMServiceEnabled=$mp.AMServiceEnabled
    AntivirusEnabled=$mp.AntivirusEnabled
    RealTimeProtection=$mp.RealTimeProtectionEnabled
    TamperProtection=$mp.IsTamperProtected
    EngineVersion=$mp.AMEngineVersion
    AVSignatureVersion=$mp.AntivirusSignatureVersion
    SignatureAgeHours=$sigAge
  }
  New-Item -ItemType Directory -Force -Path $OutputPath|Out-Null
  $file=Join-Path $OutputPath ("DefenderStatus-{0}.html"-f(Get-Date -Format "yyyyMMdd-HHmm"))
  ConvertTo-ReportHtml -Title "Microsoft Defender Status" -Data @($sum) -Meta ([ordered]@{ Computer = $env:COMPUTERNAME }) | Out-File $file -Encoding UTF8
  Write-Information "Report: $file" -InformationAction Continue
}

