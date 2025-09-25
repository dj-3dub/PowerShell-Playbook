$ErrorActionPreference = 'Stop'
Import-Module 'c:\Users\thesh\Downloads\PowerShell-Playbook\src\PowerShell-Playbook.Extensions.psd1' -Force -Verbose
$script:PlaybookConfig = [ordered]@{
    OutputRoot = Join-Path (Get-Location) 'out\smoke'
    Ticketing = [ordered]@{ BaseUrl=$null; Token=$null; ProjectKey=$null }
}
New-Item -ItemType Directory -Force -Path $script:PlaybookConfig.OutputRoot | Out-Null
try {
    Write-Output 'Running New-PlaybookReport...'
    $outFile = Join-Path $script:PlaybookConfig.OutputRoot 'smoke-report.html'
    New-PlaybookReport -Title 'Smoke Test' -Data ([pscustomobject]@{Name='x';Val=1}) -Meta @{ Test='smoke' } -OutFile $outFile | Out-Null
    Write-Output "Report: $outFile"

    Write-Output 'Running Test-BackupRestoreReadiness...'
    $b = Test-BackupRestoreReadiness -Target 'smoke-target'
    Write-Output "Backup csv: $($b.Csv)"

    Write-Output 'Running Get-CloudBaseline...'
    $c = Get-CloudBaseline -Provider 'Azure'
    Write-Output "Cloud csv: $($c.Csv)"

    Write-Output 'Running Get-O365TenantHealth...'
    $o = Get-O365TenantHealth
    Write-Output "O365 csv: $($o.Csv)"

    Write-Output 'Running Invoke-WindowsUpdateBaseline (WSUS)...'
    $w = Invoke-WindowsUpdateBaseline -Provider 'WSUS'
    Write-Output "WU csv: $($w.Csv)"

    Write-Output 'Smoke tests completed.'
} catch {
    Write-Error $_
    exit 1
}
