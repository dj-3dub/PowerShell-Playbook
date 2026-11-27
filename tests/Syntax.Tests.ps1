# Every PowerShell file in the repo must parse. Catches truncated files and
# syntax slips (e.g. "$name: ..." in a string) in scripts that have no other tests.

BeforeDiscovery {
    $root  = Split-Path -Parent $PSScriptRoot
    $files = Get-ChildItem -Path $root -Recurse -File -Include *.ps1, *.psm1, *.psd1 |
        Where-Object { $_.FullName -notmatch '[\\/](out|reports|exports)[\\/]' } |
        ForEach-Object {
            @{
                Path = $_.FullName
                Name = [IO.Path]::GetRelativePath($root, $_.FullName)
            }
        }
}

Describe 'Syntax' {
    It '<Name> parses without errors' -ForEach $files {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        $errors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" } | Should -BeNullOrEmpty
    }
}
