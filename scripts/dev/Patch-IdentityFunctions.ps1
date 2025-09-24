# Patch-IdentityFunctions.ps1
$ErrorActionPreference = 'Stop'

function Write-File($Path, $Content) {
  New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
  Set-Content -Path $Path -Value $Content -Encoding UTF8
}

# Overwrite Get-InactiveAdAccounts to RETURN the HTML path
$inactive = @'
function Get-InactiveAdAccounts {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [int]$DaysInactive = 90,
        [string]$OutputPath = "./reports"
    )

    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    $cutoff = (Get-Date).AddDays(-1 * $DaysInactive)

    # Mock data for cross-platform testing
    $rows = @(
        [pscustomobject]@{ Sam="alice"; UPN="alice@contoso.com"; LastLogon=(Get-Date).AddDays(-120) },
        [pscustomobject]@{ Sam="bob";   UPN="bob@contoso.com";   LastLogon=(Get-Date).AddDays(-91)  }
    ) | Where-Object { $_.LastLogon -le $cutoff }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $csv   = Join-Path $OutputPath ("InactiveAccounts-{0}.csv" -f $stamp)
    $html  = Join-Path $OutputPath ("InactiveAccounts-{0}.html" -f $stamp)

    $rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    $rows | ConvertTo-Html -Property Sam,UPN,LastLogon | Out-File $html -Encoding UTF8

    # Also emit the path so callers/tests can assert on it
    $html
}
'@
Set-Content -Path "src/Public/Get-InactiveAdAccounts.ps1" -Value $inactive -Encoding UTF8

# Overwrite Send-PasswordExpiryNotifications to RETURN the HTML path
$expiry = @'
function Send-PasswordExpiryNotifications {
    [CmdletBinding()]
    param(
        [int]$Days = 14,
        [string]$OutputPath = "./out",
        [switch]$Preview
    )

    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    $deadline = (Get-Date).AddDays($Days)

    $targets = @(
        [pscustomobject]@{ Name="Alice"; UPN="alice@contoso.com"; Expires=(Get-Date).AddDays(10); DaysLeft=10 },
        [pscustomobject]@{ Name="Bob";   UPN="bob@contoso.com";   Expires=(Get-Date).AddDays(2);  DaysLeft=2  }
    )

    foreach ($t in $targets) {
        $file = Join-Path $OutputPath ("PasswordNotice-{0}-{1}d.txt" -f $t.UPN,$t.DaysLeft)
@"
To: $($t.UPN)
Subject: Your password expires in $($t.DaysLeft) days

Hello $($t.Name), your password will expire on $($t.Expires).
"@ | Out-File $file -Encoding UTF8
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $html  = Join-Path $OutputPath ("PasswordExpiry-{0}.html" -f $stamp)
    $targets | ConvertTo-Html -Property Name,UPN,Expires,DaysLeft | Out-File $html -Encoding UTF8

    # Return the HTML path so tests can assert on it
    $html
}
'@
Set-Content -Path "src/Public/Send-PasswordExpiryNotifications.ps1" -Value $expiry -Encoding UTF8

Write-Host "Patched identity functions to return HTML paths." -ForegroundColor Green
