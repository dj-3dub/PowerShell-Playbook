# Lists VMware/VCF module folders in common module locations
$paths = @(
    Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules',
    Join-Path $env:ProgramFiles 'PowerShell\Modules',
    Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
)
$result = @()
foreach ($p in $paths) {
    if (Test-Path $p) {
        Write-Host "Scanning: $p"
        $dirs = Get-ChildItem -Path $p -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'VMware*' -or $_.Name -like 'VCF*' }
        foreach ($d in $dirs) {
            $result += [PSCustomObject]@{ Path = $p; Name = $d.Name; FullName = $d.FullName }
        }
    }
    else {
        Write-Host "Not found: $p"
    }
}

if ($result.Count -gt 0) {
    $result | Sort-Object Name | Format-Table -AutoSize
}
else {
    Write-Host "No VMware/VCF module folders found."
}
