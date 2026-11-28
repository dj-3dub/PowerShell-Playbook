function Get-ExchangeHygieneReport {
    <#
    .SYNOPSIS
    Per-mailbox Exchange Online hygiene: external forwarding, litigation hold, archive, and send quota.

    .DESCRIPTION
    Requires ExchangeOnlineManagement v3 and an existing Connect-ExchangeOnline session.
    When src/config/<Environment>.json sets UseMockData, sample mailboxes are used and the title is tagged [MOCK].

    .PARAMETER Environment
    Config to load: Dev (mock by default), Test or Prod.

    .PARAMETER OutputPath
    Folder for the HTML report. Default ./reports.

    .EXAMPLE
    Connect-ExchangeOnline; Get-ExchangeHygieneReport -Environment Prod

    .OUTPUTS
    Path to the HTML report.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Dev','Test','Prod')]
        [string]$Environment = 'Dev',

        [Parameter(Mandatory=$false)]
        [string]$OutputPath = './reports'
    )

    begin {
        $cfg = Get-PlaybookConfig -Environment $Environment
        New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
        Write-ToolkitLog -Level Info -Message "EXO hygiene start" -Data @{ Env=$Environment }
    }
    process {
        $usedMock = [bool]$cfg.UseMockData
        if ($usedMock) {
            Write-ToolkitLog -Level Info -Message 'Using mock EXO data (UseMockData in config)'
            $rows = @(
                [PSCustomObject]@{ Mailbox='vip@contoso.com';  ExternalForward=$false; ForwardingSmtpAddress=$null; LitigationHold=$true;  ArchiveEnabled=$true;  ProhibitSendQuota='49.5 GB (53,150,220,288 bytes)' },
                [PSCustomObject]@{ Mailbox='user@contoso.com'; ExternalForward=$true;  ForwardingSmtpAddress='external@example.com'; LitigationHold=$false; ArchiveEnabled=$false; ProhibitSendQuota='49.5 GB (53,150,220,288 bytes)' }
            )
        }
        else {
            if (-not (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue)) {
                throw 'ExchangeOnlineManagement v3 is not installed. Install-Module ExchangeOnlineManagement -Scope CurrentUser'
            }
            if (-not (Get-ConnectionInformation)) {
                throw 'No Exchange Online session. Run Connect-ExchangeOnline'
            }

            $mailboxes = Invoke-WithRetry {
                Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox `
                    -Properties ForwardingSmtpAddress, LitigationHoldEnabled, ArchiveStatus, ProhibitSendQuota
            }

            # Quotas come back as display strings with EXO v3 (e.g. "49.5 GB (53,150,220,288 bytes)"); keep them as-is.
            $rows = $mailboxes | ForEach-Object {
                [PSCustomObject]@{
                    Mailbox               = $_.UserPrincipalName
                    ExternalForward       = [bool]$_.ForwardingSmtpAddress
                    ForwardingSmtpAddress = ($_.ForwardingSmtpAddress -replace '^smtp:', '')
                    LitigationHold        = [bool]$_.LitigationHoldEnabled
                    ArchiveEnabled        = ([string]$_.ArchiveStatus -eq 'Active')
                    ProhibitSendQuota     = [string]$_.ProhibitSendQuota
                }
            }
        }

        $title = "Exchange Hygiene ($Environment){0}" -f ($(if($usedMock){" [MOCK]"}else{""}))
        $html = ConvertTo-ReportHtml -Title $title -Data $rows
        $outFile = Join-Path $OutputPath ("ExchangeHygiene-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
        $html | Out-File -FilePath $outFile -Encoding UTF8
        Write-Output $outFile
    }
    end {
        Write-ToolkitLog -Level Info -Message "EXO hygiene complete" -Data @{ Env=$Environment }
    }
}
