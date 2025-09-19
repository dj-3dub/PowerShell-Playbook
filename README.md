# ⚡ PowerShell Automation Toolkit  

A curated set of PowerShell scripts for **enterprise automation, Windows hardening, and IT operations**.  
The toolkit showcases practical approaches to solving real-world challenges in **system administration, security, and Windows management**.  

---

## 🚀 Features  
- **Enterprise automation** — Intune baselines, Conditional Access reporting, Exchange hygiene checks  
- **Windows 11 optimization** — Debloat and hardening for enterprise readiness  
- **Audit-first design** — Safe preview mode before applying changes  
- **Production practices** — Logging, config-driven design, and reusable modules  
- **Clear reporting** — Generates HTML reports for easy review and documentation  

---

## 📂 Example Scripts  
- `Get-EotConditionalAccessReport` → Generate Conditional Access policy reports  
- `Invoke-EotIntuneBaseline` → Apply Intune device configuration baselines  
- `Get-EotExchangeHygiene` → Scan Exchange Online for common misconfigurations  
- `Debloat-Win11.ps1` → Remove consumer apps and apply enterprise defaults  

---

## 🧰 Purpose  
This project demonstrates how to:  
- Automate routine administrative tasks with PowerShell  
- Structure scripts for reuse in enterprise environments  
- Apply best practices like logging, retry logic, and audit modes  

---

## 🔧 Getting Started  
```powershell
# Clone the repository
git clone https://github.com/dj-3dub/PowerShell-Automation-Toolkit.git
cd PowerShell-Automation-Toolkit

# Import the module
Import-Module .\src\EnterpriseOpsToolkit.psd1 -Force

# Run a sample command in Audit mode
.\scripts\Debloat-Win11.ps1 -Mode Audit
```

---

## 📌 Topics  
`powershell` · `automation` · `windows` · `enterprise` · `sysadmin` · `scripting` · `toolkit`  
