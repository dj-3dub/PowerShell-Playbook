# PowerShell Playbook module loader

# --- Auto-load Private helpers
Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter *.ps1 -File -ErrorAction SilentlyContinue |
ForEach-Object { . $_.FullName }

# --- Auto-load Public functions
Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter *.ps1 -File -ErrorAction SilentlyContinue |
ForEach-Object { . $_.FullName }
