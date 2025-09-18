
param(
    [switch]$SkipWinget
)
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
if (-not $SkipWinget) {
    winget install --id Git.Git -e --silent
    winget install --id Microsoft.VisualStudioCode -e --silent
    winget install --id Microsoft.DotNet.SDK.8 -e --silent
}
pwsh -NoProfile -Command "Set-PSRepository PSGallery -InstallationPolicy Trusted; Install-Module Pester,PSScriptAnalyzer,PlatyPS,Microsoft.Graph,ExchangeOnlineManagement -Scope CurrentUser -Force"
Write-Host "Dev environment ready."
