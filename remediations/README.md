# Intune Remediations

Detection and remediation script pairs for
[Intune Remediations](https://learn.microsoft.com/mem/intune/fundamentals/remediations). Intune runs `Detect.ps1`
on a schedule; when it exits `1`, Intune runs `Remediate.ps1`. These fix common causes of helpdesk tickets across
the whole fleet before anyone has to call.

| Remediation | Runs as | Detects | Fixes |
|---|---|---|---|
| `LowDiskSpace` | System | System drive below 10% or 10 GB free | Clears Windows temp, every profile's temp, the Windows Update download cache and the Delivery Optimization cache (files older than 7 days only) |
| `TeamsCacheSize` | User | New Teams cache over 1 GB | Clears it **only when Teams is closed**, otherwise retries on the next run |
| `TimeSync` | System | W32Time stopped, no external time source, or skew over 60 s | Re-enables W32Time, syncs from the domain hierarchy (or NTP when not domain-joined), forces a resync |
| `StaleWindowsUpdate` | System | No successful update install in 35 days, or update services disabled | Re-enables wuauserv/BITS and triggers a scan. Installs stay under your update rings |

## Conventions

- **Exit codes:** `0` = healthy or fixed, `1` = issue found or fix incomplete. A remediation exits `1` if the
  problem is still there afterwards, so it shows as *failed* in Intune instead of hiding.
- **One line of output.** Intune shows the last line in the device status report.
- **Self-contained.** No modules and no shared files; Intune uploads each script on its own.
- **Windows PowerShell 5.1.** That's what the Intune Management Extension runs (64-bit).
- **Conservative.** These run unattended on every device, so they never close apps the user is in, never touch
  user documents or the Recycle Bin, and leave heavy repairs (such as the Windows Update component reset) to the
  helpdesk scripts where a technician is present.
- **Thresholds are parameters with defaults.** Intune runs the scripts without arguments; the tests pass
  different values.

## Publishing

```powershell
Connect-MgGraph -Scopes DeviceManagementConfiguration.ReadWrite.All
.\Publish-IntuneRemediation.ps1 -WhatIf                     # what would be created or updated
.\Publish-IntuneRemediation.ps1 -AssignToGroupId <group-id>  # create/update all, assign daily at 09:00
```

Each folder's `remediation.json` holds the display name, description and run-as account. Re-running the
publisher updates remediations in place by display name. It uses the Microsoft Graph beta
`deviceManagement/deviceHealthScripts` endpoint.

## Adding one

1. Create `remediations/<Name>/` with `Detect.ps1`, `Remediate.ps1` and `remediation.json`.
2. Add tests to `tests/Remediations.Tests.ps1`. Every package is automatically checked for the required files,
   valid metadata, exit codes and self-containment.
