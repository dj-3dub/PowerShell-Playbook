function Get-ConditionalAccessReport {
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
        Write-ToolkitLog -Level Info -Message "CA report start" -Data @{ Env=$Environment }
    }
    process {
        $policies = $null
        $usedMock = $false
        try {
            if ($cfg.UseMockData) { throw "Mock mode enabled" }
            if (-not (Get-Module Microsoft.Graph -ListAvailable)) { throw "Microsoft.Graph module not installed" }

            if (-not (Get-MgContext)) {
                Connect-MgGraph -Scopes "Policy.Read.All","Directory.Read.All" | Out-Null
                Select-MgProfile -Name "beta"
            }
            Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop

            $policies = Invoke-WithRetry {
                Get-MgIdentityConditionalAccessPolicy -All
            }

            $policies = $policies | ForEach-Object {
                [PSCustomObject]@{
                    Name      = $_.DisplayName
                    State     = $_.State
                    AppliesTo = ($_.Conditions.Users.IncludeUsers -join ',')
                    Controls  = @(
                        if ($_.GrantControls) { 'Grant:' + ($_.GrantControls.BuiltInControls -join '+') }
                        if ($_.SessionControls) { 'Session:' + ($_.SessionControls.Keys -join '+') }
                    ) -join ' | '
                    Id        = $_.Id
                }
            }
        } catch {
            $usedMock = $true
            Write-ToolkitLog -Level Warn -Message "Falling back to mock CA data" -Data @{ Reason = $_.Exception.Message }
            $policies = @(
                [PSCustomObject]@{ Name='Require MFA for Admins'; State='Enabled'; AppliesTo='Admins'; Controls='Grant:MFA'; Id='mock-1' },
                [PSCustomObject]@{ Name='Block Legacy Auth'; State='Enabled'; AppliesTo='All Users'; Controls='Grant:Block Legacy'; Id='mock-2' }
            )
        }

        $title = "Conditional Access Report ($Environment){0}" -f ($(if($usedMock){" [MOCK]"}else{""}))
        $html = ConvertTo-ReportHtml -Title $title -Data $policies
        $outFile = Join-Path $OutputPath ("ConditionalAccess-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
        $html | Out-File -FilePath $outFile -Encoding UTF8
        Write-Output $outFile
    }
    end {
        Write-ToolkitLog -Level Info -Message "CA report complete" -Data @{ Env=$Environment }
    }
}
