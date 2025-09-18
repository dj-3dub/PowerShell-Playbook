# EnterpriseOpsToolkit (PowerShell)

A production-style module + scripts that automate common enterprise IT tasks across Entra ID/Intune, Exchange Online, and Windows endpoints.
- PS7-first, Windows-friendly (PS 5.1 supported where needed)
- Config-driven (see `config/*.json`)
- Safe-by-default (`-WhatIf`, `-Confirm`), RBAC pre-checks
- Tests (Pester), lint (PSScriptAnalyzer), CI (GitHub Actions)
- Structured logging → HTML report samples

## Quick start (Windows)
1. Install prerequisites (one-liner):
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
   winget install --id Git.Git -e ; winget install --id Microsoft.VisualStudioCode -e ; winget install --id Microsoft.DotNet.SDK.8 -e
   pwsh -NoLogo -NoProfile -Command "Set-PSRepository PSGallery -InstallationPolicy Trusted; Install-Module Pester,PSScriptAnalyzer,PlatyPS,Microsoft.Graph,ExchangeOnlineManagement -Scope CurrentUser -Force"
   ```
2. Open **VS Code** in this folder and trust the workspace.
3. Run tests:
   ```powershell
   pwsh -c "Invoke-Pester -Path tests -CI"
   ```
4. Try a sample command (mock mode – no real cloud calls):
   ```powershell
   Import-Module ./src/EnterpriseOpsToolkit.psd1 -Force
   Get-EotConditionalAccessReport -Environment Dev -OutputPath ./reports
   ```
