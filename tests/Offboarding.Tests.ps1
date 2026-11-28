# Invoke-UserOffboarding / Undo-UserOffboarding with AD, Graph, Exchange Online and SharePoint
# replaced by global stubs + Pester mocks. Nothing here touches a real directory.

BeforeAll {
    $manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PowerShellPlaybook.psd1'
    Import-Module $manifest -Force -ErrorAction Stop -WarningAction SilentlyContinue
    Push-Location $TestDrive   # Write-ToolkitLog writes to ./logs
    $mod = 'PowerShellPlaybook'

    # Stubs: real parameter names so mocks can filter on them; [CmdletBinding()] for -ErrorAction/-Confirm.
    $stubs = @{
        'Get-ADUser'                       = 'param($Identity, $Properties, $Server, $Credential)'
        'Disable-ADAccount'                = 'param($Identity, $Server, $Credential)'
        'Enable-ADAccount'                 = 'param($Identity, $Server, $Credential)'
        'Set-ADAccountPassword'            = 'param($Identity, [switch]$Reset, $NewPassword, $Server, $Credential)'
        'Set-ADUser'                       = 'param($Identity, $Description, $Clear, $Server, $Credential)'
        'Remove-ADGroupMember'             = '[CmdletBinding(SupportsShouldProcess)] param($Identity, $Members, $Server, $Credential)'
        'Add-ADGroupMember'                = 'param($Identity, $Members, $Server, $Credential)'
        'Move-ADObject'                    = 'param($Identity, $TargetPath, $Server, $Credential)'
        'Get-MgContext'                    = 'param()'
        'Revoke-MgUserSignInSession'       = 'param($UserId)'
        'Get-ConnectionInformation'        = 'param()'
        'Get-EXOMailbox'                   = 'param($Identity, $Properties)'
        'Get-MailboxAutoReplyConfiguration' = 'param($Identity)'
        'Set-Mailbox'                      = 'param($Identity, $Type, $HiddenFromAddressListsEnabled)'
        'Set-MailboxAutoReplyConfiguration' = 'param($Identity, $AutoReplyState, $InternalMessage, $ExternalMessage, $ExternalAudience)'
        'Add-MailboxPermission'            = 'param($Identity, $User, $AccessRights, $InheritanceType, $AutoMapping)'
        'Remove-MailboxPermission'         = '[CmdletBinding(SupportsShouldProcess)] param($Identity, $User, $AccessRights, $InheritanceType)'
        'Get-SPOSite'                      = 'param($IncludePersonalSite, $Limit, $Filter)'
        'Set-SPOUser'                      = 'param($Site, $LoginName, $IsSiteCollectionAdmin)'
    }
    foreach ($name in $stubs.Keys) {
        $body = $stubs[$name]
        if ($body -notmatch 'CmdletBinding') { $body = "[CmdletBinding()] $body" }
        Set-Item -Path "function:global:$name" -Value ([scriptblock]::Create($body))
    }

    $groups = 'CN=GG-Finance,OU=Groups,DC=corp,DC=local', 'CN=GG-VPN,OU=Groups,DC=corp,DC=local'

    function Set-UserMocks {
        param([bool]$Enabled = $true, [switch]$Cloud)
        $memberOf = $groups   # GetNewClosure() captures only locals
        Mock -ModuleName $mod Get-ADUser -ParameterFilter { $Identity -eq 'jdoe' } {
            [pscustomobject]@{
                SamAccountName = 'jdoe'; UserPrincipalName = 'jdoe@corp.local'; Name = 'Jane Doe'
                DistinguishedName = 'CN=Jane Doe,OU=Staff,DC=corp,DC=local'; Enabled = $Enabled
                Description = 'Finance analyst'; MemberOf = $memberOf; Manager = 'CN=Mark Manager,OU=Staff,DC=corp,DC=local'; Mail = 'jdoe@corp.local'
            }
        }.GetNewClosure()
        Mock -ModuleName $mod Get-ADUser -ParameterFilter { $Identity -like 'CN=Mark*' } {
            [pscustomobject]@{ UserPrincipalName = 'mark@corp.local' }
        }
        foreach ($c in 'Disable-ADAccount', 'Enable-ADAccount', 'Set-ADAccountPassword', 'Set-ADUser', 'Remove-ADGroupMember',
                       'Add-ADGroupMember', 'Move-ADObject', 'Revoke-MgUserSignInSession', 'Set-Mailbox',
                       'Set-MailboxAutoReplyConfiguration', 'Add-MailboxPermission', 'Remove-MailboxPermission', 'Set-SPOUser') {
            Mock -ModuleName $mod $c { }
        }
        if ($Cloud) {
            Mock -ModuleName $mod Get-MgContext { [pscustomobject]@{ Account = 'admin@corp.local' } }
            Mock -ModuleName $mod Get-ConnectionInformation { [pscustomobject]@{ State = 'Connected' } }
            Mock -ModuleName $mod Get-EXOMailbox { [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox'; HiddenFromAddressListsEnabled = $false } }
            Mock -ModuleName $mod Get-MailboxAutoReplyConfiguration { [pscustomobject]@{ AutoReplyState = 'Disabled' } }
            Mock -ModuleName $mod Get-SPOSite { [pscustomobject]@{ Url = 'https://corp-my.sharepoint.com/personal/jdoe_corp_local' } }
        }
        else {
            Mock -ModuleName $mod Get-MgContext { $null }
            Mock -ModuleName $mod Get-ConnectionInformation { $null }
            Mock -ModuleName $mod Get-SPOSite { }
        }
    }
}

AfterAll {
    Pop-Location
    foreach ($name in $stubs.Keys) { Remove-Item "function:global:$name" -ErrorAction SilentlyContinue }
    Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
}

Describe 'Invoke-UserOffboarding' {
    It '-WhatIf changes nothing but writes the snapshot and a full plan' {
        Set-UserMocks -Cloud
        $r = Invoke-UserOffboarding -Identity jdoe -TicketId CHG1 -OutputPath (Join-Path $TestDrive 'whatif') -WhatIf

        foreach ($c in 'Disable-ADAccount', 'Set-ADAccountPassword', 'Set-ADUser', 'Remove-ADGroupMember', 'Revoke-MgUserSignInSession', 'Set-Mailbox', 'Add-MailboxPermission', 'Set-SPOUser') {
            Should -Invoke -ModuleName $mod $c -Times 0 -Exactly
        }
        $r.Result | Should -Be 'Planned'
        $r.Steps | Where-Object Status -eq 'Done' | Should -BeNullOrEmpty
        $snap = Get-Content $r.Snapshot -Raw | ConvertFrom-Json
        $snap.Groups | Should -Be $groups
        $snap.Mailbox.RecipientTypeDetails | Should -Be 'UserMailbox'
        $r.Html | Should -Exist
    }

    It 'runs every step when all services are connected, delegating to the AD manager' {
        Set-UserMocks -Cloud
        $r = Invoke-UserOffboarding -Identity jdoe -TicketId CHG2 -DisabledOU 'OU=Disabled,DC=corp,DC=local' -OutputPath (Join-Path $TestDrive 'full') -Confirm:$false

        $r.Result | Should -Be 'Completed'
        ($r.Steps | Where-Object Status -ne 'Done').Step | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $mod Remove-ADGroupMember -Times 2 -Exactly
        Should -Invoke -ModuleName $mod Revoke-MgUserSignInSession -Times 1 -Exactly -ParameterFilter { $UserId -eq 'jdoe@corp.local' }
        Should -Invoke -ModuleName $mod Set-Mailbox -Times 1 -Exactly -ParameterFilter { $Type -eq 'Shared' }
        Should -Invoke -ModuleName $mod Add-MailboxPermission -Times 1 -Exactly -ParameterFilter { $User -eq 'mark@corp.local' }
        Should -Invoke -ModuleName $mod Set-SPOUser -Times 1 -Exactly -ParameterFilter { $LoginName -eq 'mark@corp.local' }
        Should -Invoke -ModuleName $mod Set-ADUser -Times 1 -Exactly -ParameterFilter { $Description -like 'Offboarded * (CHG2) by *' }
    }

    It 'marks cloud steps Skipped (not Failed) when there are no cloud sessions' {
        Set-UserMocks
        $r = Invoke-UserOffboarding -Identity jdoe -OutputPath (Join-Path $TestDrive 'adonly') -Confirm:$false

        $r.Result | Should -Be 'Completed'
        ($r.Steps | Where-Object Step -eq 'Revoke Entra sessions').Status   | Should -Be 'Skipped'
        ($r.Steps | Where-Object Step -eq 'Convert mailbox to shared').Status | Should -Be 'Skipped'
        ($r.Steps | Where-Object Step -eq 'Disable AD account').Status       | Should -Be 'Done'
    }

    It 'keeps going after a failed step and reports Failed overall' {
        Set-UserMocks -Cloud
        Mock -ModuleName $mod Revoke-MgUserSignInSession { throw 'Insufficient privileges' }
        $r = Invoke-UserOffboarding -Identity jdoe -OutputPath (Join-Path $TestDrive 'fail') -Confirm:$false

        $r.Result | Should -Be 'Failed'
        ($r.Steps | Where-Object Step -eq 'Revoke Entra sessions').Detail | Should -Be 'Insufficient privileges'
        Should -Invoke -ModuleName $mod Set-Mailbox -ParameterFilter { $Type -eq 'Shared' } -Times 1 -Exactly
    }

    It 'does not try to disable an account that is already disabled' {
        Set-UserMocks -Enabled $false
        $r = Invoke-UserOffboarding -Identity jdoe -OutputPath (Join-Path $TestDrive 'disabled') -Confirm:$false
        ($r.Steps | Where-Object Step -eq 'Disable AD account').Status | Should -Be 'Skipped'
        Should -Invoke -ModuleName $mod Disable-ADAccount -Times 0 -Exactly
    }
}

Describe 'Undo-UserOffboarding' {
    BeforeAll {
        Set-UserMocks -Cloud
        $out = Join-Path $TestDrive 'undo'
        $plan = Invoke-UserOffboarding -Identity jdoe -TicketId CHG3 -OutputPath $out -WhatIf
        $snapshotPath = $plan.Snapshot
    }

    It 'restores groups, description, OU, enabled state and mailbox from the snapshot' {
        Set-UserMocks -Cloud
        Mock -ModuleName $mod Get-ADUser -ParameterFilter { $Identity -eq 'jdoe' } {
            [pscustomobject]@{ SamAccountName = 'jdoe'; DistinguishedName = 'CN=Jane Doe,OU=Disabled,DC=corp,DC=local' }
        }
        $r = Undo-UserOffboarding -SnapshotPath $snapshotPath -OutputPath $out -Confirm:$false

        $r.Result | Should -Be 'Restored'
        Should -Invoke -ModuleName $mod Add-ADGroupMember -Times 2 -Exactly
        Should -Invoke -ModuleName $mod Move-ADObject -Times 1 -Exactly -ParameterFilter { $TargetPath -eq 'OU=Staff,DC=corp,DC=local' }
        Should -Invoke -ModuleName $mod Set-ADUser -Times 1 -Exactly -ParameterFilter { $Description -eq 'Finance analyst' }
        Should -Invoke -ModuleName $mod Enable-ADAccount -Times 1 -Exactly
        Should -Invoke -ModuleName $mod Set-Mailbox -ParameterFilter { $Type -eq 'Regular' } -Times 1 -Exactly
        Should -Invoke -ModuleName $mod Remove-MailboxPermission -ParameterFilter { $User -eq 'mark@corp.local' } -Times 1 -Exactly
    }

    It '-WhatIf restores nothing' {
        Set-UserMocks -Cloud
        $r = Undo-UserOffboarding -SnapshotPath $snapshotPath -OutputPath $out -WhatIf
        $r.Result | Should -Be 'Planned'
        Should -Invoke -ModuleName $mod Add-ADGroupMember -Times 0 -Exactly
        Should -Invoke -ModuleName $mod Enable-ADAccount -Times 0 -Exactly
    }
}
