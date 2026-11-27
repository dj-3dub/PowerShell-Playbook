# Changelog

All notable changes to PowerShell Playbook are documented here. Versions refer to the `PowerShellPlaybook` module.

---

## [Unreleased] (0.3.0)

### Changed
- **Extensions module** no longer returns placeholder numbers. Each report function queries the live system through the vendor module's session, returns a `NotConnected` row with guidance when it can't, or returns labelled sample data with `-Mock`. Rows are graded OK / Warn / Fail; HTML reports are colour-coded and HTML-encoded. Removed the no-op `-Remediate` switch and the simulated restore test.
- `Invoke-IntuneBaseline` reads Intune compliance from Graph; `-Enforce` triggers a device sync on non-compliant devices (was a 100 ms sleep). Returns device objects.
- `Get-ConditionalAccessReport` and `Get-ExchangeHygieneReport` use mock data only when the config sets `UseMockData`; otherwise they fail with guidance instead of silently showing mock data.
- Renamed to approved verbs: `Collect-SupportBundle` -> `Export-SupportBundle` (alias kept); scripts `Diagnose-SlowPC` -> `Invoke-SlowPCDiagnostics`, `Fix-DnsStack` -> `Repair-DnsStack`, `Collect-HelpdeskLogs` -> `Export-HelpdeskLogs`, `Force-PasswordReset` -> `Reset-UserPassword`, `Setup-DevEnvironment` -> `Initialize-DevEnvironment`.
- Module versions: PowerShellPlaybook 0.3.0, Extensions 0.2.0. Licensed under MIT.
- README rewritten with screenshots, architecture diagram and design notes; `docs/automation-scripts.md` rewritten to match the scripts.

### Removed
- Duplicates: `Get-LocalAdminReport` and `scripts/automation/Export-LocalAdmins.ps1` (use `Get-LocalAdminAudit`); `scripts/automation/Repair-WindowsUpdate.ps1` and `Collect-SupportBundle.ps1` (merged into the helpdesk script and module function); `New-HelpdeskTicketBundle.ps1` (broken; use `Export-HelpdeskLogs.ps1 -TicketId`).

### Fixed
- `Invoke-IntuneBaseline` failed on every run (`ForEach-Object -Parallel` with `-ArgumentList`).
- `Get-VMwareHealth` never reported snapshots (read a nonexistent `$vm.Snapshot`).
- `Get-CertificateExpiry` ignored `-ExpiresInDays`.
- `Get-DefenderStatus` and `Invoke-WinGetBaseline` did nothing on Windows PowerShell 5.1.
- `Invoke-ChocoAppSync` failed on every run (`Test-Path $x -and ...`, single-token choco arguments).
- `Repair-WindowsUpdate -Install` now downloads updates before installing them.
- `New-WinServerVmFromTemplate` help was ignored by `Get-Help` (invalid `.REQUIREMENTS` keyword).
- `Write-ToolkitLog` now writes valid JSON Lines and no longer forces verbose output.
- `-Environment Test` / `Prod` threw (missing config files).

### Added
- `PSScriptAnalyzerSettings.psd1`; CI lints `scripts/` as well as `src/`.
- Help on every exported command (enforced by a test); tests for the Extensions live paths (mocked Az/Veeam), Intune enforcement, and no-silent-mock behaviour.

---

## [0.2.0] - 2026-11-27

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

## [0.1.0] - 2025-09-24

### Added
- `scripts/dev/Invoke-WinServerVmBuild-Mock.ps1`: dry-run of a Windows Server build in vSphere (no vCenter required): 4 NICs, 2 NIC teams, CPU/memory/disk sizing and IP/DNS configuration.

### Changed
- Renamed the repository to PowerShell Playbook and restructured the README.
