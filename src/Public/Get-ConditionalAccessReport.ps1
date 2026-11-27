function Get-ConditionalAccessReport {
    <#
    .SYNOPSIS
    Exports Entra ID Conditional Access policies (name, state, scope, grant/session controls) to an HTML report.

    .DESCRIPTION
    Requires Microsoft.Graph.Identity.SignIns and Connect-MgGraph -Scopes Policy.Read.All.
    When src/config/<Environment>.json sets UseMockData, sample policies are used and the title is tagged [MOCK].

    .PARAMETER Environment
    Config to load: Dev (mock by default), Test or Prod.

    .PARAMETER OutputPath
    Folder for the HTML report. Default ./reports.

    .EXAMPLE
    Connect-MgGraph -Scopes Policy.Read.All; Get-ConditionalAccessReport -Environment Prod

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
        Write-ToolkitLog -Level Info -Message "CA report start" -Data @{ Env=$Environment }
    }
    process {
        $usedMock = [bool]$cfg.UseMockData
        if ($usedMock) {
            Write-ToolkitLog -Level Info -Message 'Using mock CA data (UseMockData in config)'
            $policies = @(
                [PSCustomObject]@{ Name='Require MFA for Admins'; State='enabled'; AppliesTo='Directory roles: 4'; Controls='Grant:mfa'; Id='mock-1' },
                [PSCustomObject]@{ Name='Block Legacy Auth'; State='enabled'; AppliesTo='All'; Controls='Grant:block'; Id='mock-2' },
                [PSCustomObject]@{ Name='Require compliant device (pilot)'; State='enabledForReportingButNotEnforced'; AppliesTo='Groups: 1'; Controls='Grant:compliantDevice'; Id='mock-3' }
            )
        }
        else {
            if (-not (Get-Command Get-MgIdentityConditionalAccessPolicy -ErrorAction SilentlyContinue)) {
                throw 'Microsoft.Graph.Identity.SignIns is not installed. Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser'
            }
            if (-not (Get-MgContext)) {
                throw 'No Microsoft Graph session. Run Connect-MgGraph -Scopes Policy.Read.All'
            }

            $policies = Invoke-WithRetry { Get-MgIdentityConditionalAccessPolicy -All } | ForEach-Object {
                $users = $_.Conditions.Users
                $scope = @(
                    if ($users.IncludeUsers -contains 'All') { 'All' }
                    elseif ($users.IncludeUsers) { "Users: $(@($users.IncludeUsers).Count)" }
                    if ($users.IncludeGroups) { "Groups: $(@($users.IncludeGroups).Count)" }
                    if ($users.IncludeRoles) { "Directory roles: $(@($users.IncludeRoles).Count)" }
                ) -join '; '
                [PSCustomObject]@{
                    Name      = $_.DisplayName
                    State     = $_.State
                    AppliesTo = $scope
                    Controls  = @(
                        if ($_.GrantControls.BuiltInControls) { 'Grant:' + ($_.GrantControls.BuiltInControls -join '+') }
                        if ($_.SessionControls.SignInFrequency.IsEnabled) { 'Session:signInFrequency' }
                    ) -join ' | '
                    Id        = $_.Id
                }
            }
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
