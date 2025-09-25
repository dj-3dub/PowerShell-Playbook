# Attempts to uninstall all VMware*/VCF* modules installed via PowerShellGet (CurrentUser scope).
# Reports any remaining module directories that may require manual deletion (admin rights for ProgramFiles).
$moduleNames = Get-Module -ListAvailable -Name 'VMware*','VCF*' | Select-Object -ExpandProperty Name -Unique
if (-not $moduleNames) {
    Write-Host "No VMware/VCF modules found to uninstall."
    exit 0
}

$failed = @()
foreach ($name in $moduleNames) {
    Write-Host "Attempting to uninstall module: $name"
    try {
        Uninstall-Module -Name $name -AllVersions -Force -ErrorAction Stop
        Write-Host "Successfully uninstalled $name"
    }
    catch {
        Write-Warning "Failed to uninstall $name via Uninstall-Module: $($_.Exception.Message)"
        $failed += $name
    }
}

# Scan common module directories for remaining VMware/VCF module folders
$paths = @(
    Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules',
    Join-Path $env:ProgramFiles 'PowerShell\Modules',
    Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
)
$leftovers = @()
foreach ($p in $paths) {
    if (Test-Path $p) {
        $dirs = Get-ChildItem -Path $p -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'VMware*' -or $_.Name -like 'VCF*' }
        foreach ($d in $dirs) {
            $leftovers += [PSCustomObject]@{ Path = $p; Name = $d.Name; FullName = $d.FullName }
        }
    }
}

if ($leftovers.Count -gt 0) {
    Write-Host "Remaining module folders found (may require manual deletion or admin rights):"
    $leftovers | Sort-Object Name | Format-Table -AutoSize
}
else {
    Write-Host "No leftover VMware/VCF module folders found."
}

if ($failed.Count -gt 0) {
    Write-Warning "Some modules failed to uninstall via Uninstall-Module. They are listed below. If they are in ProgramFiles you may need to remove them manually with admin rights."
    $failed | Sort-Object | ForEach-Object { Write-Host $_ }
}
else {
    Write-Host "All modules uninstalled via Uninstall-Module successfully."
}
