# ⚡ PowerShell Automation Toolkit

A collection of PowerShell scripts focused on automating tasks common in enterprise IT environments.  
This toolkit demonstrates how to write, organize, and test scripts that solve real-world problems for **system administration, security, and Windows management**.

---

🚀 Features

Enterprise automation → Scripts for Intune baselines, Conditional Access reporting, and Exchange hygiene

Windows 11 optimization → Debloat and hardening for enterprise readiness

Safe testing modes → Audit Mode (preview only) and Remove Mode (applies changes)

Consistent structure → Logging, config-driven design, and reusable modules
---
Readable output → HTML reports for easy review and documentation

📂 Example Scripts

Get-EotConditionalAccessReport → Generate Conditional Access HTML reports

Invoke-EotIntuneBaseline → Apply Intune device configuration baselines

Get-EotExchangeHygiene → Scan Exchange Online for common misconfigurations

Debloat-Win11.ps1 → Remove consumer bloat and apply enterprise defaults
---
🧰 Purpose

This toolkit highlights a practical approach to using PowerShell for enterprise automation.
It demonstrates:

Automating routine administrative tasks

Structuring production-ready scripts in a module format

Using best practices like logging, retry logic, and safe “audit-first” modes

🔧 Getting Started
# Clone the repository
git clone https://github.com/dj-3dub/PowerShell-Automation-Toolkit.git
cd PowerShell-Automation-Toolkit

# Import the module
Import-Module .\src\EnterpriseOpsToolkit.psd1 -Force

# Run a sample command in Audit mode
.\scripts\Debloat-Win11.ps1 -Mode Audit
---
📌 Topics

powershell · automation · windows · enterprise · sysadmin · scripting · toolkit
