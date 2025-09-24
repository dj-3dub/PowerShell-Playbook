<p align="center">
  <img src="https://raw.githubusercontent.com/PowerShell/PowerShell/master/assets/ps_black_64.svg" width="90" alt="PowerShell Logo"/>
</p>

# 🛠️ PowerShell Playbook

A modern, modular **PowerShell automation toolkit** for Windows and hybrid environments.
Designed to accelerate **IT operations, reporting, and troubleshooting** with reproducible scripts and HTML/CSV outputs.

---

## ✨ Features

- **Inventory & Reporting**
  - `Get-ServerRoleFeatureInventory` → Collects Windows Server role/feature inventory with CSV + HTML output
  - `Get-LocalAdminReport` → Audits local administrators on servers/workstations
  - `Get-CertificateExpiry` → Scans certificates nearing expiration
  - `Get-ConditionalAccessReport` → Pulls Conditional Access insights

- **Troubleshooting**
  - `Collect-SupportBundle` → Gathers logs, services, hotfixes, event logs, and network info into a zip + HTML summary
  - `Get-DefenderStatus` → Quick check of Windows Defender status

- **Automation Helpers**
  - `Invoke-WithRetry` → Retry logic wrapper
  - `Invoke-WinGetBaseline` / `Invoke-IntuneBaseline` → Baseline configuration via WinGet / Intune
  - `Write-ToolkitLog` → Consistent structured logging

- **Identity & Governance**
  - `Send-PasswordExpiryNotification` → Generate user password expiry reports & notifications
  - `Test-AdOnline`, `Test-Rbac` → Health checks and access testing

---

### 🧪 Mock VMware Windows Server Deploy (no vCenter required)

Design and present a full VMware build plan (clone → sizing → 4 NIC attach → 2× NIC Teams → IP config) without touching a real environment.

```powershell
pwsh -NoProfile -File .\scripts\dev\Invoke-WinServerVmBuild-Mock.ps1 `
  -VMName "WIN-SQL01" -Template "Win2022-Core-Golden" `
  -Datacenter "DC1" -Cluster "Prod-Cluster01" -Datastore "iSCSI-DS1" `
  -CPU 8 -MemoryGB 32 -DiskGB 200 `
  -PortGroup1 "Prod-LAN-A" -PortGroup2 "Prod-LAN-B" -PortGroup3 "Prod-LAN-A" -PortGroup4 "Prod-LAN-B" `
  -Hostname "WIN-SQL01" -IPv4 "10.20.30.40" -PrefixLength 24 -Gateway "10.20.30.1" `
  -DnsServers "10.20.30.10","1.1.1.1" `
  -OutputPath .\out
```

---

## 📂 Repo Structure

```
PowerShell-Playbook/
├── src/                          # Core module code
│   ├── PowerShellPlaybook.psd1   # Module manifest
│   ├── PowerShellPlaybook.psm1   # Module entrypoint
│   ├── Public/                   # Exported functions
│   └── Private/                  # Internal helpers
├── tests/                        # Pester tests (Reports, Identity, WindowsOnly)
├── reports/                      # Generated reports (gitignored)
├── Run-Tests.ps1                 # Lint + Test runner (Pester 5, ScriptAnalyzer)
└── Diagnose-Playbook.ps1         # Self-check diagnostics
```

---

## 🚀 Getting Started

```powershell
# Clone the repo
git clone https://github.com/dj-3dub/PowerShell-Playbook.git
cd PowerShell-Playbook

# Import the module
Import-Module ./src/PowerShellPlaybook.psd1 -Force

# List available commands
Get-Command -Module PowerShellPlaybook
```

---

## 🧪 Testing & Linting

We ship with **Pester 5** + **PSScriptAnalyzer** support:

```powershell
# Run lint + tests
.\Run-Tests.ps1 -Output Detailed

# Optional: generate NUnit XML
.\Run-Tests.ps1 -Output Detailed -NUnitXml .\test-results.xml
```

CI/CD workflow coming soon (GitHub Actions).

---

## 📊 Sample Report

`Get-ServerRoleFeatureInventory -OutputPath ./reports`

<p align="center">
  <img src="docs/images/sample-report.png" width="700" alt="Server Role Inventory Report"/>
</p>

---

## 🧩 Requirements

- Windows PowerShell 5.1 **or** PowerShell 7+
- Windows Server for role/feature inventory
- Admin rights for some functions (Defender, SupportBundle)

### Optional provider modules

The Extensions module integrates with several cloud and vendor provider modules which are optional but enable additional features:

- Az (Azure) — install `Az.Accounts` and related Az modules to enable `Get-CloudBaseline` and Azure queries.
- Microsoft Graph — install `Microsoft.Graph.Authentication` (or the Microsoft.Graph metapackage) to enable Graph-based checks.
- Exchange Online — install `ExchangeOnlineManagement` for Exchange tenant health reports.
- AWS — install `AWSPowerShell.NetCore` to enable AWS-specific baselines.
- VMware — install `VCF.PowerCLI` (recommended) to enable hypervisor reporting. If you previously had older `VMware.*` modules installed, remove them first to avoid publisher/signature conflicts.

Example (CurrentUser scope):

```powershell
Install-Module -Name Az.Accounts,Microsoft.Graph.Authentication,ExchangeOnlineManagement,AWSPowerShell.NetCore,VCF.PowerCLI -Scope CurrentUser -Force -AllowClobber
```

If you can't or don't want to install all providers, the module will still import and most functions will return warnings or no-ops when a provider is missing.

### Antivirus / Windows Defender

Some vendor SDK files (for example VMware SDK scripts) may be flagged by antivirus products during module installation or import. If you see "This script contains malicious content and has been blocked by your antivirus software" for paths under your user modules folder, whitelist the PowerShell modules location (example path):

`C:\Users\<you>\Documents\PowerShell\Modules`

Whitelisting that folder or temporarily disabling AV during module install will avoid blocked files. Prefer to re-enable AV and only whitelist trusted module folders.

### Removing old VMware modules

If you encounter publisher or signature conflicts when installing `VCF.PowerCLI`, remove older `VMware.*` modules first. A helper script is included:

```powershell
# Run from the repo root (this attempts to uninstall user-scoped VMware modules)
pwsh -NoProfile -File .\scripts\cleanup-vmware-modules.ps1
```

If the script reports leftovers in `C:\Program Files\PowerShell\Modules` you will need to remove those folders with admin rights (or run the removal in an elevated session).

---

## 📌 Topics
`powershell` · `automation` · `windows` · `enterprise` · `sysadmin` · `scripting` · `toolkit`

---

## 📜 License

MIT — free to use, modify, and share.
Contributions and improvements welcome!

---

## 🙌 Credits

Built with ❤️ by [Tim Hevein](https://github.com/dj-3dub).
Thanks to the PowerShell community for modules, best practices, and inspiration.
