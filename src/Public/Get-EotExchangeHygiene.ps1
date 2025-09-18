
function Get-EotExchangeHygiene {
    [CmdletBinding()]
    param(
        [ValidateSet('Dev','Test','Prod')]
        [string]$Environment = 'Dev',

        [Parameter(Mandatory=$false)]
        [string]$OutputPath = './reports'
    )

    begin {
        $cfgPath = Join-Path $PSScriptRoot '..\config' | Join-Path -ChildPath "$Environment.json"
        $cfg = Get-Content $cfgPath -ErrorAction Stop | ConvertFrom-Json
        New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
        Write-Log -Level Info -Message "EXO hygiene start" -Data @{ Env=$Environment }
    }
    process {
        # MOCK MODE: Replace with Get-EXO* or Graph calls later.
        $rows = @(
            [PSCustomObject]@{ Mailbox='vip@contoso.com'; ExternalForward='Disabled'; LitigationHold='Enabled'; SizeGB=18.4 },
            [PSCustomObject]@{ Mailbox='user@contoso.com'; ExternalForward='Enabled'; LitigationHold='Disabled'; SizeGB=7.2 }
        )

        $html = ConvertTo-ReportHtml -Title "Exchange Hygiene ($Environment)" -Data $rows
        $outFile = Join-Path $OutputPath ("ExchangeHygiene-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
        $html | Out-File -FilePath $outFile -Encoding UTF8
        Write-Output $outFile
    }
    end {
        Write-Log -Level Info -Message "EXO hygiene complete" -Data @{ Env=$Environment }
    }
}
