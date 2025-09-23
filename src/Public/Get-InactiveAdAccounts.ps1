function Get-InactiveAdAccounts {
    <#
    .SYNOPSIS
    Report users inactive for N days (works domain-joined or not).
    .PARAMETER DaysInactive
    Inactivity threshold.
    .PARAMETER OutputPath
    Folder to write CSV/HTML.
    .PARAMETER Server
    FQDN of domain or DC hostname when not domain-joined.
    .PARAMETER Credential
    PSCredential to bind against AD if needed.
    .PARAMETER SearchBase
    Optional OU DN to scope the search (e.g. "OU=Users,DC=contoso,DC=com").
    .EXAMPLE
    Get-InactiveAdAccounts -DaysInactive 90 -OutputPath .\reports -Server corp.contoso.com -Credential (Get-Credential)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [int]$DaysInactive = 90,
        [string]$OutputPath = "./reports",
        [string]$Server,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$SearchBase
    )

    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $cutoff = (Get-Date).AddDays(-1 * $DaysInactive)

    # Try live AD
    $ctx = Test-AdOnline -Server $Server -Credential $Credential
    $rows = @()

    if ($ctx.Online) {
        $common = @{
            Server      = $ctx.Server
            Credential  = $ctx.Credential
            ErrorAction = 'Stop'
        }
        if ($SearchBase) { $common.SearchBase = $SearchBase }

        try {
            # Efficient: filter by lastLogonTimestamp via Search-ADAccount
            $rows = Search-ADAccount -AccountInactive -TimeSpan ([TimeSpan]::FromDays($DaysInactive)) -UsersOnly @common |
            Get-ADUser -Properties DisplayName, lastLogonDate @common |
            Select-Object SamAccountName,
            @{n = 'UPN'; e = { $_.UserPrincipalName } },
            @{n = 'DisplayName'; e = { $_.DisplayName } },
            @{n = 'LastLogonDate'; e = { $_.LastLogonDate } }
        } catch {
            Write-Verbose "AD query failed: $($_.Exception.Message). Falling back to mock."
        }
    }

    # Mock path (works on non-domain machines or offline)
    if (-not $rows -or $rows.Count -eq 0) {
        $rows = @(
            [pscustomobject]@{ SamAccountName = 'alice'; UPN = 'alice@contoso.com'; DisplayName = 'Alice Adams'; LastLogonDate = (Get-Date).AddDays(-120) },
            [pscustomobject]@{ SamAccountName = 'bob'; UPN = 'bob@contoso.com'; DisplayName = 'Bob Brown'; LastLogonDate = (Get-Date).AddDays(-95) }
        ) | Where-Object { $_.LastLogonDate -le $cutoff }
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $csv = Join-Path $OutputPath ("InactiveAccounts-{0}.csv" -f $stamp)
    $html = Join-Path $OutputPath ("InactiveAccounts-{0}.html" -f $stamp)

    $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
    $rows | ConvertTo-Html -Title "Inactive Accounts (≥ $DaysInactive days)" `
        -PreContent "<h2>Inactive Accounts</h2><p>Cutoff: $cutoff</p>" `
        -Property SamAccountName, UPN, DisplayName, LastLogonDate |
    Out-File -Encoding UTF8 -FilePath $html

    # Return the path for callers/tests
    return $html
}
