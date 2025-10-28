<#
.SYNOPSIS
  Exports local Administrators group members for one or more computers.
.PARAMETER ComputerName
  One or more target computers. Default is the local machine.
.PARAMETER OutputCsv
  Path to output CSV.
.EXAMPLE
  .\Export-LocalAdmins.ps1 -ComputerName PC01,PC02 -OutputCsv .\local-admins.csv
#>
[CmdletBinding()]
param(
  [string[]]$ComputerName = $env:COMPUTERNAME,
  [string]$OutputCsv = ".\local-admins.csv"
)

$results = foreach($comp in $ComputerName){
  try {
    $group = [ADSI]"WinNT://$comp/Administrators,group"
    $members = @()
    $group.psbase.Invoke("Members") | ForEach-Object {
      $obj = $_.GetType().InvokeMember("Adspath",'GetProperty',$null,$_,$null)
      $members += $obj
    }
    foreach($m in $members){
      [pscustomobject]@{
        Computer   = $comp
        MemberPath = $m
      }
    }
  } catch {
    [pscustomobject]@{
      Computer   = $comp
      MemberPath = "ERROR: $($_.Exception.Message)"
    }
  }
}

$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
Write-Host "Wrote $($results.Count) rows to $OutputCsv"
