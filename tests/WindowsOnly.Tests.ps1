# These commands are Windows-only at runtime. On other platforms they must no-op without throwing.

BeforeAll {
    $manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PowerShellPlaybook.psd1'
    Import-Module $manifest -Force -ErrorAction Stop -WarningAction SilentlyContinue
    # Write-ToolkitLog writes to ./logs relative to the current directory.
    Push-Location $TestDrive
    $reports = Join-Path $TestDrive 'reports'
}

AfterAll {
    Pop-Location
    Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
}

Describe 'Windows-only commands' {
    It 'Get-DefenderStatus does not throw' {
        { Get-DefenderStatus -OutputPath $reports 6>$null } | Should -Not -Throw
    }

    It 'Invoke-WinGetBaseline audits without throwing' {
        { Invoke-WinGetBaseline 6>$null } | Should -Not -Throw
    }

    It 'Export-SupportBundle creates or skips without throwing' {
        { Export-SupportBundle -OutputPath $reports -WarningAction SilentlyContinue 6>$null } | Should -Not -Throw
    }

    It 'keeps the Collect-SupportBundle alias for backward compatibility' {
        (Get-Alias Collect-SupportBundle).Definition | Should -Be 'Export-SupportBundle'
    }

    Context 'On Windows' -Skip:(-not $IsWindows) {
        It 'writes a Defender status report' {
            Get-DefenderStatus -OutputPath $reports 6>$null
            Get-ChildItem $reports -Filter '*Defender*' | Should -Not -BeNullOrEmpty
        }
    }
}
