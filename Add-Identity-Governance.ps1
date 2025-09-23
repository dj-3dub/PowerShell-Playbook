# Add-Identity-Governance.ps1
[CmdletBinding()]
param(
    [string]$PublicDir = "src/Public",
    [string]$TestsDir  = "tests"
)

$ErrorActionPreference = "Stop"

function Write-File($Path, $Content) {
    $dir = Split-Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -Path $Path -Value $Content -Encoding UTF8
    Write-Host "Wrote $Path" -ForegroundColor Green
}

# 1) Get-InactiveAdAccounts.ps1
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

    $csv  = Join-Path $OutputPath ("InactiveAccounts-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
    $rows | Export-Csv -Path $csv -NoTypeInformation

    $html = Join-Path $OutputPath ("InactiveAccounts-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
    $rows | ConvertTo-Html -Property Sam,UPN,LastLogon | Out-File $html

    Write-Host "CSV: $csv`nHTML: $html"
}
'@

Write-File (Join-Path $PublicDir "Get-InactiveAdAccounts.ps1") $inactive

# 2) Send-PasswordExpiryNotifications.ps1
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
Body:
Hello $($t.Name), your password will expire on $($t.Expires).
"@ | Out-File $file -Encoding UTF8
    }

    $html = Join-Path $OutputPath ("PasswordExpiry-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
    $targets | ConvertTo-Html -Property Name,UPN,Expires,DaysLeft | Out-File $html

    Write-Host "Preview notices + summary report: $html"
}
'@

Write-File (Join-Path $PublicDir "Send-PasswordExpiryNotifications.ps1") $expiry

# 3) Pester tests
$tests = @'
Describe "Identity Governance" {
    It "Creates inactive account report (mock)" {
        Get-InactiveAdAccounts -DaysInactive 60 -OutputPath ./reports | Should -Not -BeNullOrEmpty
    }
    It "Creates password expiry notices (preview)" {
        Send-PasswordExpiryNotifications -Days 14 -Preview -OutputPath ./out | Should -Not -BeNullOrEmpty
    }
}
'@

Write-File (Join-Path $TestsDir "IdentityGovernance.Tests.ps1") $tests

Write-Host "`nDone: added Get-InactiveAdAccounts + Send-PasswordExpiryNotifications + tests." -ForegroundColor Cyan
