
# Dot-source Private helpers
Get-ChildItem -Path $PSScriptRoot/Private -Filter *.ps1 | ForEach-Object { . $_.FullName }

# Dot-source Public functions
Get-ChildItem -Path $PSScriptRoot/Public -Filter *.ps1 | ForEach-Object { . $_.FullName }
