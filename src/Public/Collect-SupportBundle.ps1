function Collect-SupportBundle {
  <#
    .SYNOPSIS
    Collects common troubleshooting artifacts into SupportBundle-<stamp> and ZIPs it.
    Also generates an HTML summary report in -OutputPath.

    .PARAMETER OutputPath
    Folder to place the bundle folder, ZIP, and HTML.

    .EXAMPLE
    Collect-SupportBundle -OutputPath .\reports
    #>
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "./reports"
  )

  New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
  $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
  $bundleDir = Join-Path $OutputPath "SupportBundle-$stamp"
  $zipPath = "$bundleDir.zip"
  $htmlPath = Join-Path $OutputPath "SupportBundle-$stamp.html"

  if ($PSCmdlet.ShouldProcess($bundleDir, "Create support bundle")) {
    New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null

    # 1) System facts
    try {
      Get-ComputerInfo | Out-File -Encoding UTF8 (Join-Path $bundleDir "ComputerInfo.txt")
    } catch {
      "Get-ComputerInfo failed: $($_.Exception.Message)" | Out-File -Encoding UTF8 (Join-Path $bundleDir "ComputerInfo.txt")
    }

    # 2) Services
    Get-Service | Sort-Object Status, DisplayName |
    Format-Table -Auto | Out-String |
    Out-File -Encoding UTF8 (Join-Path $bundleDir "Services.txt")

    # 3) Event logs (system/app last 200)
    foreach ($log in 'System', 'Application') {
      try {
        Get-WinEvent -LogName $log -MaxEvents 200 | Format-List * |
        Out-File -Encoding UTF8 (Join-Path $bundleDir "Events-$log.txt")
      } catch {
        "Get-WinEvent $log failed: $($_.Exception.Message)" |
        Out-File -Encoding UTF8 (Join-Path $bundleDir "Events-$log.txt")
      }
    }

    # 4) Networking snapshot
    ipconfig /all > (Join-Path $bundleDir "ipconfig.txt") 2>&1
    netstat -ano   > (Join-Path $bundleDir "netstat.txt")  2>&1

    # 5) Installed hotfixes
    try {
      Get-HotFix | Sort-Object InstalledOn |
      Format-Table -Auto | Out-String |
      Out-File -Encoding UTF8 (Join-Path $bundleDir "HotFix.txt")
    } catch {
      "Get-HotFix failed: $($_.Exception.Message)" |
      Out-File -Encoding UTF8 (Join-Path $bundleDir "HotFix.txt")
    }

    # ZIP it
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $bundleDir '*') -DestinationPath $zipPath

    # HTML summary
    $facts = [pscustomobject]@{
      ComputerName = $env:COMPUTERNAME
      UserName     = $env:USERNAME
      OS           = (Get-CimInstance Win32_OperatingSystem).Caption
      Version      = (Get-CimInstance Win32_OperatingSystem).Version
      LastBoot     = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
      BundleDir    = $bundleDir
      ZipPath      = $zipPath
    }

    $files = Get-ChildItem -Recurse $bundleDir | Select-Object FullName, Length, LastWriteTime

    @(
      "<h2>Support Bundle Summary</h2>"
      ($facts | ConvertTo-Html -Fragment)
      "<h3>Files</h3>"
      ($files | ConvertTo-Html -Fragment)
    ) -join "`n" | ConvertTo-Html -Title "Support Bundle $stamp" |
    Out-File -Encoding UTF8 $htmlPath

    Write-Verbose "Bundle: $bundleDir"
    Write-Verbose "Zip:    $zipPath"
    Write-Verbose "Report: $htmlPath"
  }

  # Return the HTML path so tests/callers can assert
  return $htmlPath
}
