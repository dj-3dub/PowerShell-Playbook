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
    $publicNames = (Get-ChildItem -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Public') -Filter *.ps1 -File).BaseName
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

    It 'manifest FunctionsToExport matches src/Public exactly' {
        $declared = (Import-PowerShellDataFile $manifest).FunctionsToExport
        $onDisk   = $publicNames
        Compare-Object @($declared) @($onDisk) | Should -BeNullOrEmpty -Because 'every src/Public file must be listed in the manifest and vice versa'
    }

    It '<Name> has comment-based help with a synopsis and an example' -ForEach $publicFunctions {
        $help = Get-Help $Name -Full
        $help.Synopsis | Should -Not -Match "^\s*$Name\s*[\[(]" -Because 'a synopsis that only repeats the syntax means the help block is missing or unparseable'
        $help.Synopsis | Should -Not -BeNullOrEmpty
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'does not export private helpers' {
        $exported | Should -Not -Contain 'Get-PlaybookConfig'
        $exported | Should -Not -Contain 'Invoke-WithRetry'
    }
}

Describe 'Report style' {
    It 'is defined once, in src/Shared, for both modules' {
        $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
        $withCss = Get-ChildItem $src -Recurse -Include *.ps1, *.psm1 | Where-Object { (Get-Content $_.FullName -Raw) -match '<style' }
        @($withCss).Count | Should -Be 1
        $withCss.Directory.Name | Should -Be 'Shared'
    }
}
