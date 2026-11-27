# 📑 Changelog

All notable changes to **PowerShell Playbook** will be documented here.

---

## [Unreleased]

### Fixed
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
