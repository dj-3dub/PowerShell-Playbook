# PowerShell Playbook module loader
# Private helpers are loaded but not exported; each file in Public/ defines
# one function named after the file, and only those are exported.

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter *.ps1 -File -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter *.ps1 -File -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    } catch {
        Write-Error "Failed to load $($file.FullName): $_"
    }
}

# Backward-compatible aliases for renamed commands.
Export-ModuleMember -Function $public.BaseName -Alias 'Collect-SupportBundle'
