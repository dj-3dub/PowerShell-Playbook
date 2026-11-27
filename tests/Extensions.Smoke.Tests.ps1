# Smoke tests for the PowerShell-Playbook.Extensions module.

BeforeAll {
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PowerShell-Playbook.Extensions.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
    # The extension functions write under ./out, so run them from inside TestDrive.
    Push-Location $TestDrive
}

AfterAll {
    Pop-Location
    Remove-Module PowerShell-Playbook.Extensions -ErrorAction SilentlyContinue
}

Describe 'PowerShell-Playbook.Extensions' {
    It 'exports New-PlaybookReport' {
        Get-Command New-PlaybookReport -Module PowerShell-Playbook.Extensions | Should -Not -BeNullOrEmpty
    }

    It 'New-PlaybookReport writes an HTML file' {
        $out = Join-Path $TestDrive 'pester-smoke.html'
        New-PlaybookReport -Title 'Pester Smoke' -Data ([pscustomobject]@{ Name = 'a'; Val = 1 }) -Meta @{ pester = '1' } -OutFile $out
        $out | Should -Exist
        Get-Content $out -Raw | Should -Match 'Pester Smoke'
    }

    It 'Get-CloudBaseline degrades gracefully when Az is not installed' {
        { Get-CloudBaseline -Provider Azure -WarningAction SilentlyContinue } | Should -Not -Throw
    }
}
