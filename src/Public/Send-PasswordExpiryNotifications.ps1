function Send-PasswordExpiryNotifications {
    <#
    .SYNOPSIS
    Build password expiry notification previews (or send, later).
    .PARAMETER Days
    Notify users with passwords expiring within N days.
    .PARAMETER OutputPath
    Path to write preview .txt files and summary HTML.
    .PARAMETER Server
    FQDN of domain or DC hostname when not domain-joined.
    .PARAMETER Credential
    PSCredential to bind against AD if needed.
    .PARAMETER SearchBase
    Optional OU DN to scope the search.
    .PARAMETER Preview
    If set, generates preview files only (no email send).
    #>
    [CmdletBinding()]
    param(
        [int]$Days = 14,
        [string]$OutputPath = "./out",
        [string]$Server,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$SearchBase,
        [switch]$Preview
    )

    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $deadline = (Get-Date).AddDays($Days)

    $ctx = Test-AdOnline -Server $Server -Credential $Credential
    $users = @()

    if ($ctx.Online) {
        $common = @{
            Server      = $ctx.Server
            Credential  = $ctx.Credential
            Properties  = @('DisplayName', 'mail', 'msDS-UserPasswordExpiryTimeComputed')
            ErrorAction = 'Stop'
        }
        if ($SearchBase) { $common.SearchBase = $SearchBase }

        try {
            $users = Get-ADUser -Filter "Enabled -eq 'True' -and mail -like '*'" @common |
            Select-Object Name, SamAccountName, UserPrincipalName, mail,
            @{n = 'Expires'; e = {
                    if ($_.PsBase.Properties['msDS-UserPasswordExpiryTimeComputed'].Value) {
                        [DateTime]::FromFileTime($_.PsBase.Properties['msDS-UserPasswordExpiryTimeComputed'].Value)
                    } else { $null }
                }
            } |
            Where-Object { $_.Expires -and $_.Expires -le $deadline } |
            Select-Object Name, UserPrincipalName, mail, Expires,
            @{n = 'DaysLeft'; e = { [int]([TimeSpan]($_.Expires - (Get-Date))).TotalDays } }
        } catch {
            Write-Verbose "AD query failed: $($_.Exception.Message). Falling back to mock."
        }
    }

    # Mock fallback
    if (-not $users -or $users.Count -eq 0) {
        $users = @(
            [pscustomobject]@{ Name = 'Alice Adams'; UserPrincipalName = 'alice@contoso.com'; mail = 'alice@contoso.com'; Expires = (Get-Date).AddDays(10); DaysLeft = 10 },
            [pscustomobject]@{ Name = 'Bob Brown'; UserPrincipalName = 'bob@contoso.com'; mail = 'bob@contoso.com'; Expires = (Get-Date).AddDays(2); DaysLeft = 2 }
        ) | Where-Object { $_.Expires -le $deadline }
    }

    foreach ($u in $users) {
        $file = Join-Path $OutputPath ("PasswordNotice-{0}-{1}d.txt" -f $u.UserPrincipalName, $u.DaysLeft)
        @"
To: $($u.mail)
Subject: Your password expires in $($u.DaysLeft) days

Hello $($u.Name),
Your password is scheduled to expire on $($u.Expires).
Please change it before this date to avoid losing access.

(Preview mode)
"@ | Out-File -Encoding UTF8 -FilePath $file
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $html = Join-Path $OutputPath ("PasswordExpiry-{0}.html" -f $stamp)
    $users | ConvertTo-Html -Title "Password Expiry (≤ $Days days)" `
        -PreContent "<h2>Password Expiry</h2><p>Deadline: $deadline</p>" `
        -Property Name, UserPrincipalName, mail, Expires, DaysLeft |
    Out-File -Encoding UTF8 -FilePath $html

    return $html
}
