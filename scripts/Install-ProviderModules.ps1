$ErrorActionPreference = 'Continue'
$mods = @(
    'Az.Accounts',
    'Microsoft.Graph.Authentication',
    'ExchangeOnlineManagement',
    'AWSPowerShell.NetCore',
    'VCF.PowerCLI'
)
$results = @()
foreach ($m in $mods) {
    $found = Get-Module -ListAvailable -Name $m -ErrorAction SilentlyContinue
    if ($found) {
        $results += [pscustomobject]@{ Module=$m; Status='AlreadyAvailable'; Version=$found[0].Version }
        Write-Output "$m available: $($found[0].Version)"
        continue
    }
    try {
        Write-Output "Installing $m..."
        Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        $foundAfter = Get-Module -ListAvailable -Name $m -ErrorAction SilentlyContinue
        if ($foundAfter) { $results += [pscustomobject]@{ Module=$m; Status='Installed'; Version=$foundAfter[0].Version } ; Write-Output "$m installed: $($foundAfter[0].Version)" }
        else { $results += [pscustomobject]@{ Module=$m; Status='InstallUnknown'; Version=$null } ; Write-Output "$m install result unknown" }
    } catch {
        $results += [pscustomobject]@{ Module=$m; Status='Failed'; Error=$_.Exception.Message }
        Write-Output "$m failed: $($_.Exception.Message)"
    }
}
Write-Output "\nSummary:"
$results | Format-Table -AutoSize
return $results
