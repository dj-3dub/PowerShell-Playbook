# Validates both module manifests are well-formed and point at real files.

BeforeDiscovery {
    $srcDir    = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    $manifests = @(
        @{ Name = 'PowerShellPlaybook';             Path = Join-Path $srcDir 'PowerShellPlaybook.psd1' }
        @{ Name = 'PowerShell-Playbook.Extensions'; Path = Join-Path $srcDir 'PowerShell-Playbook.Extensions.psd1' }
    )
}

Describe 'Module manifest <Name>' -ForEach $manifests {
    BeforeAll {
        $data = Import-PowerShellDataFile -Path $Path
    }

    It 'exists' {
        $Path | Should -Exist
    }

    It 'passes Test-ModuleManifest' {
        { Test-ModuleManifest -Path $Path -ErrorAction Stop } | Should -Not -Throw
    }

    It 'RootModule points to an existing file' {
        Join-Path (Split-Path -Parent $Path) $data.RootModule | Should -Exist
    }

    It 'has a valid semantic version' {
        { [version]$data.ModuleVersion } | Should -Not -Throw
    }

    It 'has an author and description' {
        $data.Author      | Should -Not -BeNullOrEmpty
        $data.Description | Should -Not -BeNullOrEmpty
    }
}
