# Config-driven report functions: mock only when the config says so, never as a silent fallback.

BeforeAll {
    $manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PowerShellPlaybook.psd1'
    Import-Module $manifest -Force -ErrorAction Stop -WarningAction SilentlyContinue
    Push-Location $TestDrive   # Write-ToolkitLog writes to ./logs
}

AfterAll {
    Pop-Location
    Remove-Module PowerShellPlaybook -ErrorAction SilentlyContinue
}

Describe 'Invoke-IntuneBaseline' {
    It 'classifies mock devices as Compliant / NonCompliant / Stale' {
        $r = Invoke-IntuneBaseline -Environment Dev -OutputPath (Join-Path $TestDrive 'r1')
        ($r | Where-Object DeviceName -eq 'PC-001').Status | Should -Be 'Compliant'
        ($r | Where-Object DeviceName -eq 'PC-002').Status | Should -Be 'NonCompliant'
        ($r | Where-Object DeviceName -eq 'PC-003').Status | Should -Be 'Stale'
        Get-ChildItem (Join-Path $TestDrive 'r1') -Filter 'IntuneBaseline-*.html' | Should -Not -BeNullOrEmpty
    }

    It 'only acts on non-compliant devices with -Enforce, and -WhatIf skips the action' {
        $r = Invoke-IntuneBaseline -Environment Dev -Enforce -WhatIf -OutputPath (Join-Path $TestDrive 'r2')
        ($r | Where-Object DeviceName -eq 'PC-002').Action | Should -Be 'SyncSkipped (WhatIf)'
        Get-ChildItem (Join-Path $TestDrive 'r2') -Filter 'IntuneBaseline-*.html' | Should -Not -BeNullOrEmpty -Because 'the report is how you review a -WhatIf plan'
        ($r | Where-Object Status -ne 'NonCompliant').Action | Should -Not -Contain 'SyncSkipped (WhatIf)'
    }

    It 'requests a sync for non-compliant devices with -Enforce' {
        $r = Invoke-IntuneBaseline -Environment Dev -Enforce -Confirm:$false -OutputPath (Join-Path $TestDrive 'r3')
        ($r | Where-Object DeviceName -eq 'PC-002').Action | Should -Be 'SyncRequested (mock)'
    }
}

Describe 'Live mode without a connection' {
    # Prod config has UseMockData = false and nothing is connected on CI. Depending on the runner image the
    # vendor module may or may not be installed, so accept either guidance message, but never mock output.
    It '<Name> fails loudly instead of falling back to mock data' -ForEach @(
        @{ Name = 'Invoke-IntuneBaseline';       Run = { Invoke-IntuneBaseline -Environment Prod -OutputPath $TestDrive } }
        @{ Name = 'Get-ConditionalAccessReport'; Run = { Get-ConditionalAccessReport -Environment Prod -OutputPath $TestDrive } }
        @{ Name = 'Get-ExchangeHygieneReport';   Run = { Get-ExchangeHygieneReport -Environment Prod -OutputPath $TestDrive } }
    ) {
        $err = $null
        try { & $Run } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty -Because 'live mode without a session must not produce a (mock) report'
        $err.Exception.Message | Should -Match 'Install-Module|Connect-(MgGraph|ExchangeOnline)'
    }
}

Describe 'Write-ToolkitLog' {
    It 'writes one compact JSON object per line' {
        $null = Get-ConditionalAccessReport -Environment Dev -OutputPath (Join-Path $TestDrive 'ca')
        $log = Get-ChildItem (Join-Path $TestDrive 'logs') -Recurse -Filter run.jsonl | Select-Object -First 1
        $lines = Get-Content $log.FullName
        $lines.Count | Should -BeGreaterThan 1
        foreach ($line in $lines) { { $line | ConvertFrom-Json } | Should -Not -Throw }
    }
}
