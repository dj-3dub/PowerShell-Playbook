function Get-ServerRoleFeatureInventory {
    [CmdletBinding()]
    param(
        [string[]]$ComputerName = @('localhost'),
        [System.Management.Automation.PSCredential]$Credential,
        [string]$OutputPath = './reports',
        [switch]$InstalledOnly,
        [switch]$IncludeSubfeatures
    )

    begin {
        if ($OutputPath) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

        $sb = {
            param($installedOnly, $includeSub)

            function _tryServerManager {
                try {
                    Import-Module ServerManager -ErrorAction Stop | Out-Null
                    Get-WindowsFeature | ForEach-Object {
                        [pscustomobject]@{
                            ComputerName = $env:COMPUTERNAME
                            Source       = 'ServerManager'
                            Name         = $_.Name
                            DisplayName  = $_.DisplayName
                            Installed    = [bool]$_.Installed
                            FeatureType  = if ($_.FeatureType) { $_.FeatureType.ToString() } else { $null }
                            DependsOn    = ($_.DependsOn | Select-Object -ExpandProperty Name) -join ','
                            Parent       = $_.Parent
                            Note         = $null
                        }
                    }
                } catch {
                    $null
                }
            }

            function _tryDism {
                $raw = & dism.exe /online /Get-Features /Format:Table 2>&1
                if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }

                foreach ($line in $raw) {
                    if ($line -match '^\s*([\w\.\-_]+)\s+:\s+(\w+)\s*$') {
                        [pscustomobject]@{
                            ComputerName = $env:COMPUTERNAME
                            Source       = 'DISM'
                            Name         = $matches[1]
                            DisplayName  = $matches[1]
                            Installed    = ($matches[2] -match 'Enable|Enabled')
                            FeatureType  = $null
                            DependsOn    = $null
                            Parent       = $null
                            Note         = $null
                        }
                    }
                }
            }

            $data = _tryServerManager
            if (-not $data) { $data = _tryDism }

            if ($installedOnly) { $data = $data | Where-Object { $_.Installed } }
            if (-not $includeSub) { $data = $data | Where-Object { -not $_.Parent } }

            $data
        }

        $all = New-Object System.Collections.Generic.List[object]
    }

    process {
        foreach ($cn in $ComputerName) {
            try {
                if ($cn -in @('localhost', '127.0.0.1', '::1', $env:COMPUTERNAME)) {
                    $result = & $sb $InstalledOnly.IsPresent $IncludeSubfeatures.IsPresent
                } else {
                    $icm = @{
                        ComputerName = $cn
                        ScriptBlock  = $sb
                        ArgumentList = @($InstalledOnly.IsPresent, $IncludeSubfeatures.IsPresent)
                        ErrorAction  = 'Stop'
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) { $icm.Credential = $Credential }
                    $result = Invoke-Command @icm
                }

                if ($result) { [void]$all.AddRange($result) }
                else {
                    [void]$all.Add([pscustomobject]@{
                            ComputerName = $cn
                            Source       = $null
                            Name         = $null
                            DisplayName  = $null
                            Installed    = $null
                            FeatureType  = $null
                            DependsOn    = $null
                            Parent       = $null
                            Note         = 'Failed to inventory roles/features (ServerManager/DISM unavailable?)'
                        })
                }
            } catch {
                [void]$all.Add([pscustomobject]@{
                        ComputerName = $cn
                        Source       = $null
                        Name         = $null
                        DisplayName  = $null
                        Installed    = $null
                        FeatureType  = $null
                        DependsOn    = $null
                        Parent       = $null
                        Note         = $_.Exception.Message
                    })
            }
        }
    }

    end {
        $objects = $all.ToArray()

        if ($OutputPath) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
            $csv = Join-Path $OutputPath "ServerRoles-$stamp.csv"
            $html = Join-Path $OutputPath "ServerRoles-$stamp.html"

            $objects | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv

            $title = 'Server Role/Feature Inventory'
            $pre = "<h2>$title</h2><p>Generated: $(Get-Date)</p>"

            $objects |
            Sort-Object -Property ComputerName, Installed, DisplayName -Descending |
            ConvertTo-Html -Title $title -PreContent $pre `
                -Property ComputerName, Source, DisplayName, Name, Installed, FeatureType, Parent, DependsOn, Note |
            Out-File -Encoding UTF8 $html

            Write-Verbose "CSV:  $csv"
            Write-Verbose "HTML: $html"
        }

        $objects
    }
}
