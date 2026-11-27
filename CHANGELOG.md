# 📑 Changelog

All notable changes to **PowerShell Playbook** will be documented here.

---

## [Unreleased]

### Fixed
- Five helpdesk scripts failed to parse and could not run: four used `"$var: ..."` in strings (`Test-VpnDiagnostics`, `Test-EndpointPreflight`, `Reset-BrowserProfile`, `Test-BitLockerHealth`), and `Test-MailboxCapacityAndRetention` was truncated mid-statement.
- `Test-MailboxCapacityAndRetention`: completed the missing archive check, results and CSV export; request quota/retention/archive properties from `Get-EXOMailbox`; size parsing no longer depends on Exchange types and reads exact byte counts; mailboxes with no retention policy no longer error.
- `Reset-TeamsCache`: supports new Teams (`ms-teams.exe`, MSIX cache) alongside classic. It no longer deletes the classic Teams install folder or the Outlook Teams Meeting Add-in.
- `Force-PasswordReset`: `-WhatIf` no longer sets ChangePasswordAtLogon. It and `Unlock-UserAccount` exit 1 on failure.
- `New-BatchAdUser`: removed the hardcoded default password. Accounts get unique random passwords (shown once, never written to the report) and must change them at first logon.
- `Test-BitLockerHealth`: WMI filter never matched (`'C:\'` vs `'C:'`); switched to `Get-CimInstance` for PowerShell 7.
- Identity and network-performance scripts wrote logs under `scripts/out/` while the toolkit's log viewer read `out/`; they now share `out/HelpdeskLogs`.
- Replaced PowerShell 7-only `?:` and `??` operators (Extensions module, `Reset-Proxy`, `Export-ADUsers-LDAP`) so everything runs on Windows PowerShell 5.1.
- `New-PlaybookReport` joined metadata with a literal `\n`.
- CI now runs green on Windows and Linux (removed a setup action that no longer exists; pinned Pester and PSScriptAnalyzer).
- Rewrote the Pester suite: one setup block per file, cross-platform paths, output isolated to `$TestDrive`.
- `Export-ADObjects-NoRSAT.ps1` failed to parse; config lookup broke on case-sensitive filesystems; `Collect-SupportBundle` threw off Windows.

### Changed
- Standardized on the name **PowerShell Playbook** (manifest, URLs, report branding). Module version bumped to 0.2.0 with a real GUID.
- Module exports an explicit function list; private helpers are no longer exported. Renamed `Get-EotConfig` to `Get-PlaybookConfig`.
- Removed expired self-signed Authenticode signatures from `src/`.
- Moved `install-provider-modules.ps1` to `scripts/Install-ProviderModules.ps1`; renamed `docs/README_Additions.md` to `docs/automation-scripts.md`.

### Removed
- Committed output (`exports/*.csv`, `.OutputRoot/`), now gitignored.
- One-off repo maintenance scripts (`scripts/dev/Fix-*`, `Patch-*`, `Add-*`, `Tidy-Repo.ps1`, etc.) and the unused root `config/dev.json`.

### Added
- CI fails on syntax that Windows PowerShell 5.1 cannot run (`PSUseCompatibleSyntax`).
- Tests: every `.ps1`/`.psm1`/`.psd1` must parse; behavioral tests with mocked AD for password reset (`-WhatIf`, failure exit code), Teams cache reset (both clients, install folder untouched), and password generation.
- Test runs no longer write any files into the repo.
- `scripts/Export-ADObjects-NoRSAT.ps1`: `-Mock` mode to simulate AD objects for offline testing and CI (use `-MockCount` to control rows).

---

## [2025-09-24] – 🚀 Repo Refresh & VMware Mock Deploy

### ✨ Added
- **Mock VMware Deployment Script**  
  `scripts/dev/Invoke-WinServerVmBuild-Mock.ps1`  
  - Simulates a Windows Server deployment in VMware (no vCenter required).  
  - Attaches 4 NICs and configures 2 NIC teams.  
  - Handles sizing (CPU, memory, disk) and IP/DNS config.  
  - Ideal for demonstrating automation workflows in interviews or labs.

### 📝 Changed
- **README.md**
  - Updated repo name to **PowerShell Playbook**
  - Improved layout and section flow
  - Added VMware mock deployment usage example
  - Cleaned up repo structure section
  - Fixed formatting in code snippets
  - Refined Topics list for discoverability

### ✅ Improvements
- Project docs now align with current scope of the repo
- README is recruiter-ready and portfolio-friendly
