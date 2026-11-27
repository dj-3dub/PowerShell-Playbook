# These commands are Windows-only at runtime. On other platforms they must no-op without throwing.

BeforeAll {
    $manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PowerShellPlaybook.psd1'
    Import-Module $manifest -Force -ErrorAction Stop -WarningAction SilentlyContinue
    $reports = Join-Path $TestDrive 'reports'
}

AfterAll {
    Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
}

Describe 'Windows-only commands' {
    It 'Get-DefenderStatus does not throw' {
        { Get-DefenderStatus -OutputPath $reports 6>$null } | Should -Not -Throw
    }

    It 'Invoke-WinGetBaseline audits without throwing' {
        { Invoke-WinGetBaseline 6>$null } | Should -Not -Throw
    }

    It 'Collect-SupportBundle creates or skips without throwing' {
        { Collect-SupportBundle -OutputPath $reports -WarningAction SilentlyContinue 6>$null } | Should -Not -Throw
    }

    Context 'On Windows' -Skip:(-not $IsWindows) {
        It 'writes a Defender status report' {
            Get-DefenderStatus -OutputPath $reports 6>$null
            Get-ChildItem $reports -Filter '*Defender*' | Should -Not -BeNullOrEmpty
        }
    }
}
