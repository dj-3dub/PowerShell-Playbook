
function Invoke-EotIntuneBaseline {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [ValidateSet('Dev','Test','Prod')]
        [string]$Environment = 'Dev',

        [int]$ThrottleLimit = 16,

        [switch]$Enforce
    )

    begin {
        $cfgPath = Join-Path $PSScriptRoot '..\config' | Join-Path -ChildPath "$Environment.json"
        $cfg = Get-Content $cfgPath -ErrorAction Stop | ConvertFrom-Json
        Write-Log -Level Info -Message "Intune baseline start" -Data @{ Env=$Environment; Enforce=$Enforce.IsPresent }

        # Demo device list (mock mode)
        $script:Devices = @(
            [PSCustomObject]@{ deviceName='PC-001'; compliant=$true },
            [PSCustomObject]@{ deviceName='PC-002'; compliant=$false }
        )
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
        Write-Log -Level Info -Message "Intune baseline complete" -Data @{ Env=$Environment; Enforce=$Enforce.IsPresent }
    }
}
