<p align="center">
  <img src="https://raw.githubusercontent.com/PowerShell/PowerShell/master/assets/ps_black_64.svg" width="90" alt="PowerShell Logo"/>
</p>
# ⚙️ PowerShell-Playbook

A modular collection of PowerShell scripts and functions designed for automating Windows system configuration, diagnostics, and IT operations workflows.  
This playbook supports enterprise-grade automation as well as homelab experimentation, offering reusable tooling for endpoint management, baselining, and support tasks.

---

## 📁 Repository Layout

```
PowerShell-Playbook/
├── scripts/
│   ├── automation/       # Automation and repair scripts (new)
│   ├── dev/              # Development and testing utilities
│   ├── ops/              # Operational support scripts
│   ├── tools/            # Helper scripts and functions
│   └── data/             # Static data files (CSV, JSON, XML)
├── src/                  # Public and private module functions
├── out/                  # Generated artifacts (exports, reports, support bundles)
├── docs/                 # Documentation and images
└── tests/                # Pester and smoke tests
```

---

## 🧰 New Automation Scripts (2025-10-28)

| Script | Purpose |
|--------|----------|
| **Diagnose-SlowPC.ps1** | Performs system health diagnostics (CPU, RAM, disk I/O, event logs). |
| **Repair-WindowsUpdate.ps1** | Resets Windows Update components and clears cache issues. |
| **Invoke-ChocoAppSync.ps1** | Syncs Chocolatey package installs and updates missing software. |
| **Export-LocalAdmins.ps1** | Enumerates local administrator accounts and exports to CSV. |
| **Collect-SupportBundle.ps1** | Gathers system logs and support data into a single ZIP bundle. |
| **Reset-Proxy.ps1** | Views, sets, or clears WinHTTP and WinINET proxy configurations. |
| **Repair-WindowsSearch.ps1** | Repairs the Windows Search index and restarts related services. |
| **Fix-DnsStack.ps1** | Flushes and resets DNS client stack settings. |

---

## 🚀 Quick Start

Clone and open the playbook:

```powershell
git clone https://github.com/dj-3dub/PowerShell-Playbook.git
cd PowerShell-Playbook
```

Unblock all scripts and run a diagnostic sample:

```powershell
Get-ChildItem .\scripts -Recurse -Filter *.ps1 | Unblock-File
.\scripts\automation\Diagnose-SlowPC.ps1 -WhatIf
```

---

## 🧩 Use Cases

- Automate common Windows maintenance and recovery tasks  
- Capture system health data for troubleshooting or reporting  
- Standardize workstation or server configuration baselines  
- Build repeatable, script-driven workflows for lab or enterprise use  

---

## 📜 License

MIT License © Tim Heverin
