function Undo-UserOffboarding {
    <#
    .SYNOPSIS
    Reverses Invoke-UserOffboarding using the snapshot it wrote (for example, a user offboarded by mistake).

    .DESCRIPTION
    Reads the .snapshot.json produced by Invoke-UserOffboarding and, step by step through ShouldProcess:
      - moves the account back to its original OU
      - restores the original AD description
      - re-adds every recorded group membership
      - re-enables the account (only if it was enabled before offboarding)
      - converts the mailbox back to its original type, turns off the auto-reply, unhides it,
        and removes the delegate's Full Access                     (Exchange Online)

    Not reversible: the password was set to a random value that was never recorded, and revoked Entra
    sessions stay revoked. After undoing, issue a new temporary password with
    scripts/helpdesk/Reset-UserPassword.ps1. OneDrive delegation is left in place for the delegate's
    work in progress; remove it manually if required.

    .PARAMETER SnapshotPath
    Path to the Offboarding-*.snapshot.json file.

    .PARAMETER Server
    Domain controller or domain FQDN for the AD cmdlets. Defaults to the server recorded in the snapshot.

    .PARAMETER Credential
    Credential for the AD cmdlets.

    .PARAMETER OutputPath
    Folder for the CSV and HTML report. Default ./reports.

    .EXAMPLE
    Undo-UserOffboarding -SnapshotPath .\reports\Offboarding-jdoe-CHG0012345-20261127-101500.snapshot.json -WhatIf

    .OUTPUTS
    PSCustomObject with Identity, Result, Steps, Csv and Html.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })][string]$SnapshotPath,
        [string]$Server,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$OutputPath = './reports'
    )

    if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
        throw 'The ActiveDirectory module (RSAT) is required.'
    }

    $snap = Get-Content -Path $SnapshotPath -Raw | ConvertFrom-Json
    if ($snap.SchemaVersion -ne 1) { throw "Unsupported snapshot schema version: $($snap.SchemaVersion)" }

    $ad = @{ ErrorAction = 'Stop' }
    if (-not $Server -and $snap.Server) { $Server = $snap.Server }
    if ($Server)     { $ad.Server = $Server }
    if ($Credential) { $ad.Credential = $Credential }

    $upn = $snap.UserPrincipalName
    # The account may have been moved; find it by sAMAccountName rather than the old DN.
    $user = Get-ADUser -Identity $snap.SamAccountName @ad
    $exo = [bool]((Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) -and (Get-ConnectionInformation))

    $steps = New-Object System.Collections.Generic.List[object]
    $run = {
        param([string]$Name, [string]$Target, [string]$Action, [scriptblock]$Do, [string]$SkipReason)
        $row = [pscustomobject]@{ Step = $Name; Status = $null; Detail = $null }
        if ($SkipReason) { $row.Status = 'Skipped'; $row.Detail = $SkipReason }
        elseif ($PSCmdlet.ShouldProcess($Target, $Action)) {
            try {
                $detail = & $Do
                $row.Status = 'Restored'; $row.Detail = if ($detail) { [string]$detail } else { $Action }
            }
            catch { $row.Status = 'Failed'; $row.Detail = $_.Exception.Message }
        }
        else { $row.Status = 'Planned'; $row.Detail = $Action }
        $steps.Add($row)
    }

    $originalOU = $snap.DistinguishedName -replace '^CN=.+?(?<!\\),', ''
    $currentOU  = $user.DistinguishedName -replace '^CN=.+?(?<!\\),', ''
    & $run 'Move back to original OU' $snap.SamAccountName "Move to $originalOU" {
        Move-ADObject -Identity $user.DistinguishedName -TargetPath $originalOU @ad
    } $(if ($originalOU -eq $currentOU) { 'Already in original OU' })

    & $run 'Restore description' $snap.SamAccountName "Set description: '$($snap.Description)'" {
        if ($snap.Description) { Set-ADUser -Identity $snap.SamAccountName -Description $snap.Description @ad }
        else { Set-ADUser -Identity $snap.SamAccountName -Clear Description @ad }
    }

    $groups = @($snap.Groups | Where-Object { $_ })
    & $run 'Restore group memberships' $snap.SamAccountName "Add back to $($groups.Count) group(s)" {
        $failed = @()
        foreach ($g in $groups) {
            try { Add-ADGroupMember -Identity $g -Members $snap.SamAccountName @ad }
            catch { $failed += ($g -replace '^CN=([^,]+),.*$', '$1') }
        }
        if ($failed) { throw "Restored $($groups.Count - $failed.Count) of $($groups.Count); failed: $($failed -join ', ')" }
        "Re-added to $($groups.Count) group(s)"
    } $(if (-not $groups) { 'No groups recorded' })

    & $run 'Re-enable AD account' $snap.SamAccountName 'Enable-ADAccount' {
        Enable-ADAccount -Identity $snap.SamAccountName @ad
        'Enabled. Issue a new temporary password with Reset-UserPassword.ps1'
    } $(if (-not $snap.Enabled) { 'Account was already disabled before offboarding' })

    $exoSkip = if (-not $snap.Mailbox) { 'No mailbox state in snapshot' } elseif (-not $exo) { 'No Exchange Online session (Connect-ExchangeOnline)' }
    $originalType = if ($snap.Mailbox -and $snap.Mailbox.RecipientTypeDetails -eq 'SharedMailbox') { 'Shared' } else { 'Regular' }

    & $run 'Restore mailbox type' $upn "Set-Mailbox -Type $originalType" {
        Set-Mailbox -Identity $upn -Type $originalType -ErrorAction Stop
    } $exoSkip

    & $run 'Restore auto-reply' $upn "Set auto-reply to $(if ($snap.Mailbox) { $snap.Mailbox.AutoReplyState })" {
        Set-MailboxAutoReplyConfiguration -Identity $upn -AutoReplyState $snap.Mailbox.AutoReplyState -ErrorAction Stop
    } $exoSkip

    & $run 'Restore address list visibility' $upn "HiddenFromAddressListsEnabled = $(if ($snap.Mailbox) { $snap.Mailbox.Hidden })" {
        Set-Mailbox -Identity $upn -HiddenFromAddressListsEnabled ([bool]$snap.Mailbox.Hidden) -ErrorAction Stop
    } $exoSkip

    & $run 'Remove mailbox delegation' $upn "Remove FullAccess for $($snap.DelegateTo)" {
        Remove-MailboxPermission -Identity $upn -User $snap.DelegateTo -AccessRights FullAccess -InheritanceType All -Confirm:$false -ErrorAction Stop
    } $(if ($exoSkip) { $exoSkip } elseif (-not $snap.DelegateTo) { 'No delegate recorded' })

    $rows = $steps.ToArray()
    $result = if ($rows.Status -contains 'Failed') { 'Failed' } elseif ($rows.Status -contains 'Restored') { 'Restored' } else { 'Planned' }

    New-Item -ItemType Directory -Force -Path $OutputPath -WhatIf:$false | Out-Null
    $base = Join-Path $OutputPath ("OffboardingUndo-{0}-{1}" -f $snap.SamAccountName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $rows | Export-PlaybookCsv -Path "$base.csv"
    $meta = [ordered]@{ User = $upn; Ticket = $snap.TicketId; Snapshot = (Split-Path $SnapshotPath -Leaf); Result = $result }
    [IO.File]::WriteAllText("$base.html", (ConvertTo-ReportHtml -Title "Offboarding undo: $upn" -Data $rows -Meta $meta), [Text.Encoding]::UTF8)
    Write-ToolkitLog -Level Info -Message "Offboarding undo $($result.ToLower()): $upn" -Data @{ Snapshot = $SnapshotPath }

    [pscustomobject]@{ Identity = $upn; Result = $result; Steps = $rows; Csv = "$base.csv"; Html = "$base.html" }
}
