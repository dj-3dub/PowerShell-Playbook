function Invoke-UserOffboarding {
    <#
    .SYNOPSIS
    Offboards a user across Active Directory, Entra ID, Exchange Online and OneDrive, with a snapshot for undo.

    .DESCRIPTION
    Before changing anything, the user's current state is written to a JSON snapshot (AD groups, OU,
    description, enabled state, mailbox type/visibility/auto-reply). Undo-UserOffboarding restores from it.

    Steps, in order (security first, then clean-up and hand-over):
      1. Disable the AD account
      2. Reset the password to a random value nobody knows
      3. Revoke Entra ID sign-in sessions and refresh tokens    (Microsoft Graph)
      4. Stamp the AD description with date, ticket and operator
      5. Remove AD group memberships (the primary group is kept)
      6. Move the account to -DisabledOU                        (if given)
      7. Convert the mailbox to shared                          (Exchange Online)
      8. Set an internal/external auto-reply                    (Exchange Online)
      9. Hide the mailbox from the address lists                (Exchange Online)
     10. Grant the delegate Full Access to the mailbox          (Exchange Online)
     11. Grant the delegate access to the user's OneDrive       (SharePoint Online)

    Every state-changing step goes through ShouldProcess, so -WhatIf produces the full plan without changing
    anything. Cloud steps use the existing Connect-MgGraph / Connect-ExchangeOnline / Connect-SPOService
    session and are marked Skipped (not failed) when that session is missing. A failing step is recorded and
    the remaining steps still run; the function's overall result is Failed if any step failed.

    .PARAMETER Identity
    sAMAccountName or UPN of the user.

    .PARAMETER TicketId
    Change/ticket reference, written to the AD description, snapshot and report names.

    .PARAMETER DelegateTo
    UPN that receives mailbox and OneDrive access. Defaults to the user's AD manager.

    .PARAMETER DisabledOU
    Distinguished name of the OU for disabled accounts. If omitted, the account is not moved.

    .PARAMETER AutoReplyMessage
    Auto-reply text. Defaults to a short notice that names the delegate.

    .PARAMETER Server
    Domain controller or domain FQDN for the AD cmdlets.

    .PARAMETER Credential
    Credential for the AD cmdlets.

    .PARAMETER OutputPath
    Folder for the snapshot (JSON) and report (CSV + HTML). Default ./reports.

    .EXAMPLE
    Invoke-UserOffboarding -Identity jdoe -TicketId CHG0012345 -WhatIf
    Show every step that would run, with no changes.

    .EXAMPLE
    Connect-MgGraph -Scopes User.ReadWrite.All; Connect-ExchangeOnline; Connect-SPOService -Url https://contoso-admin.sharepoint.com
    Invoke-UserOffboarding -Identity jdoe -TicketId CHG0012345 -DisabledOU 'OU=Disabled Users,DC=contoso,DC=com'

    .OUTPUTS
    PSCustomObject with Identity, Result, Steps, Snapshot, Csv and Html.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Wraps a just-generated random password that is never displayed or stored.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$Identity,
        [string]$TicketId,
        [string]$DelegateTo,
        [string]$DisabledOU,
        [string]$AutoReplyMessage,
        [string]$Server,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$OutputPath = './reports'
    )

    if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
        throw 'The ActiveDirectory module (RSAT) is required. Install RSAT: Active Directory Domain Services tools.'
    }

    $ad = @{ ErrorAction = 'Stop' }
    if ($Server)     { $ad.Server = $Server }
    if ($Credential) { $ad.Credential = $Credential }

    $user = Get-ADUser -Identity $Identity -Properties Description, MemberOf, Manager, Mail, Enabled @ad
    $upn = $user.UserPrincipalName
    $operator = [Environment]::UserName
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $label = if ($TicketId) { "$($user.SamAccountName)-$TicketId" } else { $user.SamAccountName }

    if (-not $DelegateTo -and $user.Manager) {
        try { $DelegateTo = (Get-ADUser -Identity $user.Manager @ad).UserPrincipalName } catch { Write-Verbose "Manager lookup failed: $_" }
    }

    $graph = [bool]((Get-Command Get-MgContext -ErrorAction SilentlyContinue) -and (Get-MgContext))
    $exo   = [bool]((Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) -and (Get-ConnectionInformation))
    $spo   = [bool](Get-Command Get-SPOSite -ErrorAction SilentlyContinue)

    # -- Snapshot (read-only, always written, even under -WhatIf) --------------------------------------------
    $mailbox = $null
    if ($exo) {
        try {
            $mbx = Get-EXOMailbox -Identity $upn -Properties RecipientTypeDetails, HiddenFromAddressListsEnabled -ErrorAction Stop
            $auto = Get-MailboxAutoReplyConfiguration -Identity $upn -ErrorAction Stop
            $mailbox = [ordered]@{
                RecipientTypeDetails = [string]$mbx.RecipientTypeDetails
                Hidden               = [bool]$mbx.HiddenFromAddressListsEnabled
                AutoReplyState       = [string]$auto.AutoReplyState
            }
        }
        catch { Write-Verbose "Mailbox snapshot skipped: $_" }
    }

    $snapshot = [ordered]@{
        SchemaVersion     = 1
        TakenAt           = (Get-Date).ToString('o')
        TakenBy           = $operator
        TicketId          = $TicketId
        SamAccountName    = $user.SamAccountName
        UserPrincipalName = $upn
        DistinguishedName = $user.DistinguishedName
        Enabled           = [bool]$user.Enabled
        Description       = $user.Description
        Groups            = @($user.MemberOf)
        DelegateTo        = $DelegateTo
        Mailbox           = $mailbox
        Server            = $Server
    }
    New-Item -ItemType Directory -Force -Path $OutputPath -WhatIf:$false | Out-Null
    $snapshotPath = Join-Path $OutputPath "Offboarding-$label-$stamp.snapshot.json"
    [IO.File]::WriteAllText($snapshotPath, ($snapshot | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8)

    # -- Step runner -----------------------------------------------------------------------------------------
    $steps = New-Object System.Collections.Generic.List[object]
    $run = {
        param([string]$Name, [string]$Target, [string]$Action, [scriptblock]$Do, [string]$SkipReason)
        $row = [pscustomobject]@{ Step = $Name; Status = $null; Detail = $null }
        if ($SkipReason) {
            $row.Status = 'Skipped'; $row.Detail = $SkipReason
        }
        elseif ($PSCmdlet.ShouldProcess($Target, $Action)) {
            try {
                $detail = & $Do
                $row.Status = 'Done'; $row.Detail = if ($detail) { [string]$detail } else { $Action }
            }
            catch {
                $row.Status = 'Failed'; $row.Detail = $_.Exception.Message
                Write-ToolkitLog -Level Warn -Message "Offboarding step '$Name' failed for $upn" -Data @{ Error = $_.Exception.Message; Ticket = $TicketId }
            }
        }
        else {
            $row.Status = 'Planned'; $row.Detail = $Action
        }
        $steps.Add($row)
    }
    $needGraph = 'No Microsoft Graph session (Connect-MgGraph -Scopes User.ReadWrite.All)'
    $needExo   = 'No Exchange Online session (Connect-ExchangeOnline)'
    $noDelegate = 'No -DelegateTo given and the user has no AD manager'

    Write-ToolkitLog -Level Info -Message "Offboarding start: $upn" -Data @{ Ticket = $TicketId; Operator = $operator; Snapshot = $snapshotPath }

    # -- Security first --------------------------------------------------------------------------------------
    & $run 'Disable AD account' $user.SamAccountName 'Disable-ADAccount' {
        Disable-ADAccount -Identity $user.DistinguishedName @ad
    } $(if (-not $user.Enabled) { 'Already disabled' })

    & $run 'Reset password' $user.SamAccountName 'Set a random password nobody knows' {
        $pw = ConvertTo-SecureString (New-RandomPassword -Length 24) -AsPlainText -Force
        Set-ADAccountPassword -Identity $user.DistinguishedName -Reset -NewPassword $pw @ad
        'Password reset to a random value (not recorded)'
    }

    & $run 'Revoke Entra sessions' $upn 'Revoke-MgUserSignInSession' {
        Revoke-MgUserSignInSession -UserId $upn -ErrorAction Stop | Out-Null
        'Refresh tokens and sessions revoked'
    } $(if (-not $graph) { $needGraph })

    # -- Clean-up --------------------------------------------------------------------------------------------
    $note = "Offboarded $(Get-Date -Format 'yyyy-MM-dd')"
    if ($TicketId) { $note += " ($TicketId)" }
    $note += " by $operator"
    & $run 'Stamp description' $user.SamAccountName "Set description: '$note'" {
        Set-ADUser -Identity $user.DistinguishedName -Description $note @ad
    }

    $groups = @($user.MemberOf)
    & $run 'Remove group memberships' $user.SamAccountName "Remove from $($groups.Count) group(s)" {
        $failed = @()
        foreach ($g in $groups) {
            try { Remove-ADGroupMember -Identity $g -Members $user.DistinguishedName -Confirm:$false @ad }
            catch { $failed += ($g -replace '^CN=([^,]+),.*$', '$1') }
        }
        if ($failed) { throw "Removed $($groups.Count - $failed.Count) of $($groups.Count); failed: $($failed -join ', ')" }
        "Removed from $($groups.Count) group(s); list kept in snapshot"
    } $(if (-not $groups) { 'No group memberships' })

    & $run 'Move to disabled OU' $user.SamAccountName "Move to $DisabledOU" {
        Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledOU @ad
    } $(if (-not $DisabledOU) { 'No -DisabledOU given' })

    # -- Mailbox and OneDrive hand-over ----------------------------------------------------------------------
    $exoSkip = if (-not $exo) { $needExo } elseif (-not $mailbox) { 'User has no Exchange Online mailbox' }

    & $run 'Convert mailbox to shared' $upn 'Set-Mailbox -Type Shared' {
        Set-Mailbox -Identity $upn -Type Shared -ErrorAction Stop
    } $(if ($exoSkip) { $exoSkip } elseif ($mailbox.RecipientTypeDetails -eq 'SharedMailbox') { 'Already shared' })

    if (-not $AutoReplyMessage) {
        $AutoReplyMessage = "$($user.Name) is no longer with the organization."
        if ($DelegateTo) { $AutoReplyMessage += " Please contact $DelegateTo." }
    }
    & $run 'Set auto-reply' $upn 'Enable internal and external auto-reply' {
        Set-MailboxAutoReplyConfiguration -Identity $upn -AutoReplyState Enabled -InternalMessage $AutoReplyMessage `
            -ExternalMessage $AutoReplyMessage -ExternalAudience All -ErrorAction Stop
    } $exoSkip

    & $run 'Hide from address lists' $upn 'Set-Mailbox -HiddenFromAddressListsEnabled $true' {
        Set-Mailbox -Identity $upn -HiddenFromAddressListsEnabled $true -ErrorAction Stop
    } $exoSkip

    & $run 'Delegate mailbox' $upn "Grant FullAccess to $DelegateTo" {
        Add-MailboxPermission -Identity $upn -User $DelegateTo -AccessRights FullAccess -InheritanceType All -AutoMapping $true -ErrorAction Stop | Out-Null
    } $(if ($exoSkip) { $exoSkip } elseif (-not $DelegateTo) { $noDelegate })

    & $run 'Delegate OneDrive' $upn "Make $DelegateTo a site collection admin of the user's OneDrive" {
        $site = Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Owner -eq '$upn'" -ErrorAction Stop | Select-Object -First 1
        if (-not $site) { return 'User has no OneDrive site' }
        Set-SPOUser -Site $site.Url -LoginName $DelegateTo -IsSiteCollectionAdmin $true -ErrorAction Stop | Out-Null
        "Access granted: $($site.Url)"
    } $(if (-not $spo) { 'SharePoint Online module not loaded (Connect-SPOService)' } elseif (-not $DelegateTo) { $noDelegate })

    # -- Report ----------------------------------------------------------------------------------------------
    $rows = $steps.ToArray()
    $result = if ($rows.Status -contains 'Failed') { 'Failed' }
              elseif ($rows.Status -contains 'Done') { 'Completed' }
              else { 'Planned' }

    $csv  = Join-Path $OutputPath "Offboarding-$label-$stamp.csv"
    $html = Join-Path $OutputPath "Offboarding-$label-$stamp.html"
    $rows | Export-PlaybookCsv -Path $csv
    $meta = [ordered]@{ User = $upn; Ticket = $TicketId; Delegate = $DelegateTo; Operator = $operator; Result = $result }
    [IO.File]::WriteAllText($html, (ConvertTo-ReportHtml -Title "Offboarding: $upn" -Data $rows -Meta $meta), [Text.Encoding]::UTF8)

    Write-ToolkitLog -Level Info -Message "Offboarding $($result.ToLower()): $upn" -Data @{ Ticket = $TicketId; Report = $html }

    [pscustomobject]@{
        Identity = $upn
        Result   = $result
        Steps    = $rows
        Snapshot = $snapshotPath
        Csv      = $csv
        Html     = $html
    }
}
