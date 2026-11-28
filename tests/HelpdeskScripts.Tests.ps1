# Behavioral tests for helpdesk scripts that change state. AD cmdlets and user
# profile folders are faked, so these run on any OS without a domain.

BeforeAll {
    $root      = Split-Path -Parent $PSScriptRoot
    $helpdesk  = Join-Path $root 'scripts/helpdesk'
    $logsDir   = Join-Path $root 'out/HelpdeskLogs'
    $before    = @(Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue).FullName

    # Stand-ins so Get-Command finds the AD cmdlets and Pester can mock them.
    function Get-ADUser            { param($Identity, $Properties) }
    function Set-ADAccountPassword { param($Identity, [switch]$Reset, $NewPassword) }
    function Set-ADUser            { param($Identity, $ChangePasswordAtLogon) }
}

AfterAll {
    # The scripts log to <repo>/out/HelpdeskLogs; remove only the files these tests created.
    Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue |
        Where-Object { $before -notcontains $_.FullName } |
        Remove-Item -Force
}

Describe 'Reset-UserPassword.ps1' {
    BeforeAll {
        $script = Join-Path $helpdesk 'Reset-UserPassword.ps1'
    }

    BeforeEach {
        Mock Get-ADUser { [pscustomobject]@{ SamAccountName = 'jdoe'; Enabled = $true } }
        Mock Set-ADAccountPassword { }
        Mock Set-ADUser { }
        Mock Write-Host { }
        # Answer "Y" to prompts; supply a SecureString when the password is requested.
        Mock Read-Host {
            if ($AsSecureString) { ConvertTo-SecureString 'Temp-Passw0rd!' -AsPlainText -Force } else { 'Y' }
        }
    }

    It 'changes nothing under -WhatIf (including ChangePasswordAtLogon)' {
        & $script -Identity jdoe -WhatIf
        Should -Invoke Set-ADAccountPassword -Times 0 -Exactly
        Should -Invoke Set-ADUser -Times 0 -Exactly
    }

    It 'resets the password and requires change at next logon' {
        & $script -Identity jdoe
        Should -Invoke Set-ADAccountPassword -Times 1 -Exactly -ParameterFilter { $Identity -eq 'jdoe' -and $Reset }
        Should -Invoke Set-ADUser -Times 1 -Exactly -ParameterFilter { $ChangePasswordAtLogon -eq $true }
    }

    It 'exits non-zero when the reset fails' {
        Mock Set-ADAccountPassword { throw 'Access is denied' }
        & $script -Identity jdoe
        $LASTEXITCODE | Should -Be 1
        Should -Invoke Set-ADUser -Times 0 -Exactly
    }
}

Describe 'Reset-TeamsCache.ps1' {
    BeforeAll {
        $script = Join-Path $helpdesk 'Reset-TeamsCache.ps1'
    }

    BeforeEach {
        # Fake user profile under TestDrive, built with the same Join-Path calls the script uses.
        $savedLocal, $savedRoaming = $env:LOCALAPPDATA, $env:APPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive "local-$(New-Guid)"
        $env:APPDATA      = Join-Path $TestDrive "roaming-$(New-Guid)"

        $newCache     = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
        $classicCache = Join-Path $env:APPDATA 'Microsoft\Teams'
        $classicBin   = Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\Update.exe'
        $meetingAddin = Join-Path $env:LOCALAPPDATA 'Microsoft\TeamsMeetingAddin'

        foreach ($dir in $newCache, $classicCache, $meetingAddin) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir 'cache.dat') -Value 'x'
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $classicBin) | Out-Null
        Set-Content -Path $classicBin -Value 'binary'

        Mock Get-Process { }
        Mock Start-Process { }
        Mock Write-Host { }
    }

    AfterEach {
        $env:LOCALAPPDATA, $env:APPDATA = $savedLocal, $savedRoaming
    }

    It 'removes nothing under -WhatIf' {
        & $script -Client Both -WhatIf
        Join-Path $newCache 'cache.dat'     | Should -Exist
        Join-Path $classicCache 'cache.dat' | Should -Exist
    }

    It 'clears new and classic Teams caches' {
        & $script -Client Both
        Get-ChildItem $newCache -Force     | Should -BeNullOrEmpty
        Get-ChildItem $classicCache -Force | Should -BeNullOrEmpty
    }

    It 'leaves the classic install folder and Outlook meeting add-in intact' {
        & $script -Client Both
        $classicBin                         | Should -Exist
        Join-Path $meetingAddin 'cache.dat' | Should -Exist
    }

    It 'auto-detects installed clients' {
        Remove-Item (Join-Path $env:APPDATA 'Microsoft') -Recurse -Force
        Remove-Item (Join-Path $env:LOCALAPPDATA 'Microsoft\Teams') -Recurse -Force
        & $script
        Get-ChildItem $newCache -Force | Should -BeNullOrEmpty
    }
}

Describe 'New-BatchAdUser.ps1 temporary passwords' {
    BeforeAll {
        # Load just the generator function from the script.
        $path = Join-Path $root 'scripts/automation/New-BatchAdUser.ps1'
        $ast  = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $fn   = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-TemporaryPassword' }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }

    It 'meets AD complexity (upper, lower, digit, symbol) at length 16' {
        1..50 | ForEach-Object {
            $p = New-TemporaryPassword
            $p.Length | Should -Be 16
            $p | Should -MatchExactly '[A-Z]'
            $p | Should -MatchExactly '[a-z]'
            $p | Should -Match '\d'
            $p | Should -Match '[^A-Za-z0-9]'
        }
    }

    It 'is unique per call' {
        $set = 1..200 | ForEach-Object { New-TemporaryPassword } | Sort-Object -Unique
        @($set).Count | Should -Be 200
    }

    It 'has no hardcoded default password' {
        Get-Content $path -Raw | Should -Not -Match 'P@ssw0rd'
    }
}
