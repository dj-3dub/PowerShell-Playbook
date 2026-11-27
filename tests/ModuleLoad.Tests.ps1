# Verifies the module imports cleanly and every public function is exported.

BeforeDiscovery {
    $publicDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Public'
    $publicFunctions = Get-ChildItem -Path $publicDir -Filter *.ps1 -File |
        ForEach-Object { @{ Name = $_.BaseName } }
}

BeforeAll {
    $manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PowerShellPlaybook.psd1'
    Import-Module $manifest -Force -ErrorAction Stop -WarningAction SilentlyContinue
    $exported = (Get-Command -Module PowerShellPlaybook).Name
}

AfterAll {
    Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
}

Describe 'PowerShellPlaybook module' {
    It 'imports without error' {
        { Import-Module $manifest -Force -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Not -Throw
    }

    It 'exports <Name> (from src/Public/<Name>.ps1)' -ForEach $publicFunctions {
        $exported | Should -Contain $Name
    }

    It 'does not export private helpers' {
        $exported | Should -Not -Contain 'Get-EotConfig'
        $exported | Should -Not -Contain 'Invoke-WithRetry'
    }
}
