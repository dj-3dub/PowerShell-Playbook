function Get-ServerRoleFeatureInventory {
    <#
    .SYNOPSIS
    Inventories installed Windows Server roles and features on one or more servers (ServerManager, falling back to DISM).

    .PARAMETER ComputerName
    Target servers. Remote targets use Invoke-Command. Default localhost.

    .PARAMETER Credential
    Credential for remoting.

    .PARAMETER OutputPath
    Folder for the CSV and HTML report. Default ./reports.

    .PARAMETER InstalledOnly
    Only include installed roles/features.

    .PARAMETER IncludeSubfeatures
    Include sub-features as well as top-level roles/features.

    .EXAMPLE
    Get-ServerRoleFeatureInventory -ComputerName FS01, SQL01 -InstalledOnly
    #>
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

            $objects | Export-PlaybookCsv -Path $csv

            $sorted = @($objects | Sort-Object -Property ComputerName, Installed, DisplayName -Descending)
            ConvertTo-ReportHtml -Title 'Server Role/Feature Inventory' -Data $sorted `
                -Property ComputerName, Source, DisplayName, Name, Installed, FeatureType, Parent, DependsOn, Note `
                -Meta ([ordered]@{ Servers = ($ComputerName -join ', '); InstalledOnly = [bool]$InstalledOnly }) |
            Out-File -Encoding UTF8 $html

            Write-Verbose "CSV:  $csv"
            Write-Verbose "HTML: $html"
        }

        $objects
    }
}
