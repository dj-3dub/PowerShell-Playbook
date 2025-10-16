Describe 'Export-ADObjects-NoRSAT -Mock mode' {
    It 'creates a CSV file with expected columns' {
        $out = Join-Path $PSScriptRoot '..\exports\test_users_mock.csv' | Resolve-Path -ErrorAction SilentlyContinue
        if ($out) { Remove-Item $out -Force -ErrorAction SilentlyContinue }

        & pwsh -NoProfile -File (Join-Path $PSScriptRoot '..\scripts\Export-ADObjects-NoRSAT.ps1') -ObjectType User -Mock -MockCount 5 -OutputPath (Join-Path $PSScriptRoot '..\exports\test_users_mock.csv') -NoBOM:$true

        $file = Join-Path $PSScriptRoot '..\exports\test_users_mock.csv'
        Test-Path $file | Should -BeTrue

        $csv = Import-Csv $file -ErrorAction Stop
        $csv.Count | Should -BeGreaterThan 0

        # Basic column checks
        $expected = @('Name','SamAccountName')
        foreach ($col in $expected) { $csv[0].PSObject.Properties.Name -contains $col | Should -BeTrue }

        # Cleanup
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    }
}
