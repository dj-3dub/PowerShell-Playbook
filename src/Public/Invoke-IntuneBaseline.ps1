function Invoke-IntuneBaseline {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [ValidateSet('Dev','Test','Prod')]
        [string]$Environment = 'Dev',

        [int]$ThrottleLimit = 16,

        [switch]$Enforce
    )

    begin {
        $cfg = Get-PlaybookConfig -Environment $Environment

        Write-ToolkitLog -Level Info -Message "Intune baseline start" -Data @{
            Env     = $Environment
            Enforce = $Enforce.IsPresent
            Mock    = $cfg.UseMockData
        }

        if ($cfg.UseMockData) {
            $script:Devices = @(
                [PSCustomObject]@{ deviceName='PC-001'; compliant=$true },
                [PSCustomObject]@{ deviceName='PC-002'; compliant=$false }
            )
        } else {
            # TODO: implement real device fetch (Graph/Intune)
            Write-ToolkitLog -Level Warn -Message "Non-mock Intune device path not implemented yet; using empty set."
            $script:Devices = @()
        }
    }

    process {
        $scriptBlock = {
            param($d, $enforce)
            $result = [PSCustomObject]@{
                DeviceName = $d.deviceName
                Compliant  = $d.compliant
                Remediated = $false
            }
            if (-not $d.compliant -and $enforce) {
                if ($PSCmdlet.ShouldProcess($d.deviceName, "Remediate baseline drift")) {
                    Start-Sleep -Milliseconds 100
                    $result.Remediated = $true
                }
            }
            return $result
        }

        $results = $script:Devices | ForEach-Object -Parallel $scriptBlock -ThrottleLimit $ThrottleLimit -ArgumentList $Enforce.IsPresent
        $html = ConvertTo-ReportHtml -Title "Intune Baseline ($Environment)" -Data $results
        $outFile = Join-Path './reports' ("IntuneBaseline-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
        New-Item -ItemType Directory -Force -Path './reports' | Out-Null
        $html | Out-File -FilePath $outFile -Encoding UTF8
        Write-Output $outFile
    }

    end {
        Write-ToolkitLog -Level Info -Message "Intune baseline complete" -Data @{ Env=$Environment; Enforce=$Enforce.IsPresent }
    }
}
