# Export-ADObjects-NoRSAT in -Mock mode needs no domain, so it runs on any platform.

BeforeAll {
    $script = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Export-ADObjects-NoRSAT.ps1'
}

Describe 'Export-ADObjects-NoRSAT -Mock' {
    It 'writes a CSV with the requested number of rows and expected columns' {
        $out = Join-Path $TestDrive 'users_mock.csv'

        & $script -ObjectType User -Mock -MockCount 5 -OutputPath $out -NoBOM 6>$null | Out-Null

        $out | Should -Exist
        $csv = @(Import-Csv $out)
        $csv.Count | Should -Be 5
        $csv[0].PSObject.Properties.Name | Should -Contain 'Name'
        $csv[0].PSObject.Properties.Name | Should -Contain 'SamAccountName'
    }
}
