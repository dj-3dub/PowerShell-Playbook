function Get-ExchangeHygieneReport {
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
        $rows = $null
        $usedMock = $false
        try {
            if ($cfg.UseMockData) { throw "Mock mode enabled" }
            if (-not (Get-Module ExchangeOnlineManagement -ListAvailable)) { throw "ExchangeOnlineManagement not installed" }

            if (-not (Get-PSSession | Where-Object { $_.ComputerName -like "*.outlook.com" })) {
                Connect-ExchangeOnline -ShowBanner:$false | Out-Null
            }

            $mailboxes = Invoke-WithRetry {
                Get-EXOMailbox -ResultSize 1000 -PropertySets Quota, Archive, LitigationHold
            }

            $rows = $mailboxes | Select-Object `
                UserPrincipalName,
                DisplayName,
                @{n='ExternalForward';e={$null -ne $_.ForwardingSmtpAddress}},
                @{n='ForwardingSmtpAddress';e={$_.ForwardingSmtpAddress}},
                @{n='LitigationHold';e={$_.LitigationHoldEnabled}},
                @{n='ProhibitSendQuotaGB';e={[math]::Round(($_.ProhibitSendQuota.Value.ToBytes() / 1GB),2)}},
                @{n='TotalItemSizeGB';e={
                    try { [math]::Round(($_.TotalItemSize.Value.ToBytes() / 1GB),2) } catch { $null }
                }}
        } catch {
            $usedMock = $true
            Write-ToolkitLog -Level Warn -Message "Falling back to mock EXO data" -Data @{ Reason = $_.Exception.Message }
            $rows = @(
                [PSCustomObject]@{ Mailbox='vip@contoso.com'; ExternalForward=$false; ForwardingSmtpAddress=$null; LitigationHold=$true; ProhibitSendQuotaGB=50; TotalItemSizeGB=18.4 },
                [PSCustomObject]@{ Mailbox='user@contoso.com'; ExternalForward=$true; ForwardingSmtpAddress='external@example.com'; LitigationHold=$false; ProhibitSendQuotaGB=50; TotalItemSizeGB=7.2 }
            )
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
