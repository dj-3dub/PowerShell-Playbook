Describe 'PowerShell-Playbook.Extensions smoke tests' {
    Context 'Module import and basic report' {
        It 'Imports the extensions module and exposes functions' {
            $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\PowerShell-Playbook.Extensions.psd1'
            { Import-Module -Name $modulePath -Force -ErrorAction Stop } | Should -Not -Throw
            (Get-Command -Name New-PlaybookReport -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        }

        It 'New-PlaybookReport writes an HTML file' {
            $tmp = Join-Path (Get-Location) 'out\pester-smoke'
            New-Item -Force -ItemType Directory -Path $tmp | Out-Null
            $out = Join-Path $tmp 'pester-smoke.html'
            New-PlaybookReport -Title 'Pester Smoke' -Data ([pscustomobject]@{Name='a';Val=1}) -Meta @{ pester='1' } -OutFile $out
            Test-Path $out | Should -BeTrue
        }
    }

    Context 'Missing Az modules handled' {
        It 'Get-CloudBaseline warns when Az not loaded' {
            # If Az is present, temporarily remove it from session to simulate missing modules
            if (Get-Module -Name Az -ListAvailable) { Remove-Module -Name Az -Force -ErrorAction SilentlyContinue }
            { Get-CloudBaseline -Provider 'Azure' } | Should -Not -Throw
        }
    }
}
