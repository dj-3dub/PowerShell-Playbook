# PowerShell Playbook

[![CI](https://github.com/dj-3dub/PowerShell-Playbook/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/dj-3dub/PowerShell-Playbook/actions/workflows/ci.yml)

PowerShell automation for helpdesk and endpoint operations, in two parts:

- **Helpdesk Toolkit** (`scripts/helpdesk/`): a menu launcher for common diagnostics and repairs (Outlook/Teams/browser resets, OneDrive and OST repair, VPN, network performance and BitLocker checks, AD unlock and password reset)
- **`PowerShellPlaybook` module** (`src/`): identity, security and endpoint reports for AD, Entra ID, Intune, Exchange Online and Windows, with mock data when no tenant or domain is reachable

Linted with PSScriptAnalyzer and tested with Pester on Windows and Linux in CI.

---

# 🔹 Overview  
Modern IT operations face a recurring challenge: **high ticket volume caused by repetitive, time‑consuming, and easily automatable endpoint issues.**

This toolkit centralizes proven support procedures into consistent, modular PowerShell workflows that:

- Accelerate problem resolution  
- Improve reliability and consistency  
- Reduce manual troubleshooting effort  
- Provide actionable diagnostics and structured logs  
- Enable efficient support across teams  

---

# 🔹 Toolkit Capabilities  

## 🛠 Automated Repairs
- Printer subsystem repair  
- Microsoft Teams cache rebuild  
- Outlook profile reset  
- Network stack repair (DNS/Winsock/TCP)  
- Windows Update component repair  
- Browser (Chrome/Edge) profile resets  
- OneDrive sync repair (soft or full reset)  
- Outlook OST backup, scan, and rebuild  

---

## 🩺 Diagnostics & System Health
- Endpoint pre-flight checks  
- VPN diagnostics (connectivity, routing, DNS)  
- BitLocker status and TPM reporting  
- Mailbox quota & retention policy analysis  
- Comprehensive helpdesk log collection (ZIP bundle)  

These modules mirror real-world troubleshooting steps used by senior support engineers.

---

# 🧱 Project Structure
```
scripts/
│
├── helpdesk/
│   ├── Invoke-HelpdeskToolkit.ps1
│   ├── <diagnostic modules>
│   ├── <repair modules>
│   ├── <logging modules>
│   └── <reporting modules>
│
└── out/
```

---

# 🚀 Usage

## Windows PowerShell
```powershell
cd .\scripts\helpdesk\
.\Invoke-HelpdeskToolkit.ps1
```

## WSL → Windows PowerShell
```bash
cd ~/projects/PowerShell-Playbook
WINPATH=$(wslpath -w .)

powershell.exe -ExecutionPolicy Bypass -Command "
  Set-Location '$WINPATH';
  ./scripts/helpdesk/Invoke-HelpdeskToolkit.ps1
"
```

---

# 🔮 Forward Vision
Future enhancements may include:

- WinGet-based standard software builds  
- Endpoint performance snapshots  
- GPO/RSoP troubleshooting  
- Profile corruption detection  
- Network latency and bottleneck analysis  
- Advanced OneDrive/Outlook resilience modules  

---

# 👤 Author
**Tim Heverin**  
Systems & Infrastructure Engineering  
Windows • PowerShell • Automation • Cloud • Endpoint Operations  
Chicago, IL  
GitHub: **dj-3dub**

---

<br>
<p align="center">
  <sub>Made with ❤️ by <strong>Tim Heverin</strong></sub>
</p>
