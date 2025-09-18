
function Get-EotConditionalAccessReport {
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
        Write-Log -Level Info -Message "CA report start" -Data @{ Env=$Environment }
    }
    process {
        # MOCK MODE: Use fixture data until Graph is wired up.
        $policies = @(
            [PSCustomObject]@{ Name='Require MFA for Admins'; State='Enabled'; AppliesTo='Admins'; Controls='MFA'; Notes='Mock sample' },
            [PSCustomObject]@{ Name='Block Legacy Auth'; State='Enabled'; AppliesTo='All Users'; Controls='Block Legacy Auth'; Notes='Mock sample' }
        )

        $html = ConvertTo-ReportHtml -Title "Conditional Access Report ($Environment)" -Data $policies
        $outFile = Join-Path $OutputPath ("ConditionalAccess-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
        $html | Out-File -FilePath $outFile -Encoding UTF8
        Write-Output $outFile
    }
    end {
        Write-Log -Level Info -Message "CA report complete" -Data @{ Env=$Environment }
    }
}
