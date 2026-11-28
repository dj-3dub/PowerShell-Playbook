# Automation scripts

Standalone scripts outside the modules. Each has comment-based help (`Get-Help <script> -Full`)
unless noted, and state-changing scripts support `-WhatIf`.

## Endpoint triage and repair (`scripts/automation/`)

| Script | Purpose | Example |
|---|---|---|
| `Invoke-SlowPCDiagnostics.ps1` | "My PC is slow" triage: top processes, startup items, disk, recent errors, pending updates; HTML + TXT report | `.\Invoke-SlowPCDiagnostics.ps1 -Hours 3` |
| `Repair-DnsStack.ps1` | Show or repair DNS/Winsock; set DNS servers per interface | `.\Repair-DnsStack.ps1 -Repair` |
| `Repair-WindowsSearch.ps1` | Restart Windows Search, rebuild the index, optionally SFC/DISM | `.\Repair-WindowsSearch.ps1 -ResetIndex -RunSfc` |
| `Reset-Proxy.ps1` | Show, clear or set WinHTTP and WinINET proxy | `.\Reset-Proxy.ps1 -Set -Proxy proxy:8080 -Bypass '*.corp.local'` |

The Windows Update repair and log bundle live in the Helpdesk Toolkit
(`scripts/helpdesk/Repair-WindowsUpdate.ps1`, `scripts/helpdesk/Export-HelpdeskLogs.ps1`).

## Provisioning

| Script | Purpose | Example |
|---|---|---|
| `New-BatchAdUser.ps1` | Bulk-create AD users from CSV with groups; unique random passwords, change at first logon; `-Offline` preview | `.\New-BatchAdUser.ps1 -CsvPath .\scripts\data\new-hires.csv -Offline` |
| `Invoke-StandardBuild.ps1` | Install the standard app set from `config/software-build.json` (WinGet) | `.\Invoke-StandardBuild.ps1 -ConfigPath .\config\software-build.json` |
| `Invoke-ChocoAppSync.ps1` | Bootstrap Chocolatey, upgrade all, ensure a `packages.config` | `.\Invoke-ChocoAppSync.ps1 -PackagesConfig .\packages.config` |
| `../Initialize-DevEnvironment.ps1` | Workstation setup for working on this repo (Git, VS Code, .NET SDK, Pester, PSScriptAnalyzer, Graph, EXO) | `.\scripts\Initialize-DevEnvironment.ps1` |

## Active Directory export (`scripts/`)

| Script | Purpose | Example |
|---|---|---|
| `Export-ADObjects-NoRSAT.ps1` | Export users/computers/groups over LDAP without RSAT; `-Mock` generates sample data | `.\Export-ADObjects-NoRSAT.ps1 -ObjectType User -Mock -MockCount 50` |
| `Invoke-ADExport.ps1` | Run several exports defined in `ad-export.config.json` | `.\Invoke-ADExport.ps1 -Mock` |
| `Export-ADUsers-LDAP.ps1` | Focused user export via `System.DirectoryServices`, LDAPS optional | `.\Export-ADUsers-LDAP.ps1 -Server dc01 -SearchBase 'DC=corp,DC=local' -UseLDAPS` |

## Windows 11 hardening and debloat (`scripts/`)

All four audit first and support `-WhatIf`; the setting scripts have `-Revert`. For managed devices, prefer
Intune or Group Policy. These suit standalone builds, labs and unmanaged machines.

| Script | Purpose | Example |
|---|---|---|
| `Invoke-Win11Debloat.ps1` | Runs the three below. `-Mode Audit` (default) shows the plan and writes the report; `-Mode Remove` applies | `.\Invoke-Win11Debloat.ps1` |
| `Remove-PreinstalledApps.ps1` | Remove Appx packages matching `config/debloat-appx.json` (keep-list always wins); report shows each package's outcome | `.\Remove-PreinstalledApps.ps1 -AllUsers -WhatIf` |
| `Set-ConsumerExperience.ps1` | Turn off suggested apps, Spotlight, tips and widgets news via policy; `-Revert` removes the values | `.\Set-ConsumerExperience.ps1 -Revert` |
| `Set-EnterpriseDefaults.ps1` | Disable unsolicited Remote Assistance and Xbox services, set telemetry to Required; pick with `-Setting`, undo with `-Revert` | `.\Set-EnterpriseDefaults.ps1 -Setting Telemetry` |

## Module tooling (`scripts/`)

| Script | Purpose |
|---|---|
| `Publish-Module.ps1` | Stage `PowerShellPlaybook` into `out/PowerShellPlaybook` for `Publish-Module` or copying to a module path |
| `Install-ProviderModules.ps1` | Check for the vendor modules used in live mode and install missing ones for the current user |
| `dev/Invoke-WinServerVmBuild-Mock.ps1` | Dry-run walkthrough of the vSphere build that `New-WinServerVmFromTemplate` performs |
| `dev/Start-ReportServer.sh` | Serve `./reports` with an index page for viewing reports from another machine |
