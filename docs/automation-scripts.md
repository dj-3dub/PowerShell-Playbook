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

These scripts have no comment-based help yet. Read the `param()` block before running them.

| Script | Purpose |
|---|---|
| `Invoke-Win11Debloat.ps1` | Orchestrates the three below. `-Mode Audit` (default) reports; `-Mode Remove` applies |
| `Remove-PreinstalledApps.ps1` | Remove Appx packages matching `config/debloat-appx.json` (keep/remove patterns) |
| `Set-ConsumerExperience.ps1` | Disable consumer features (suggested apps, tips) via policy registry keys |
| `Set-EnterpriseDefaults.ps1` | Disable Remote Assistance, Xbox services, and set telemetry to Basic |

## Module tooling (`scripts/`)

| Script | Purpose |
|---|---|
| `Publish-Module.ps1` | Stage `PowerShellPlaybook` into `out/PowerShellPlaybook` for `Publish-Module` or copying to a module path |
| `Install-ProviderModules.ps1` | Check for the vendor modules used in live mode and install missing ones for the current user |
| `dev/Invoke-WinServerVmBuild-Mock.ps1` | Dry-run walkthrough of the vSphere build that `New-WinServerVmFromTemplate` performs |
| `dev/Start-ReportServer.sh` | Serve `./reports` with an index page for viewing reports from another machine |
