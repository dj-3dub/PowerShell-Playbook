function Get-LocalAdminAudit {
    <#
      .SYNOPSIS
      Audits members of the local Administrators group on one or more computers.

      .DESCRIPTION
      - Enumerates local Administrators, resolves member type/name
      - Supports remoting (Invoke-Command) for remote hosts
      - Optional baseline allow-list (JSON or CSV) to flag unexpected members
      - Writes CSV + HTML reports and returns objects

      .PARAMETER ComputerName
      One or more target computers. Defaults to localhost.

      .PARAMETER Credential
      PSCredential used for remoting.

      .PARAMETER BaselinePath
      Path to a JSON or CSV allow-list.
        JSON example:
          { "Allowed": [ { "Name":"BUILTIN\\Administrators" }, { "Name":"CONTOSO\\Server Admins" } ] }
        CSV example (header required):
          Name
          BUILTIN\Administrators
          CONTOSO\Server Admins

      .PARAMETER OutputPath
      Folder to write CSV/HTML (default: ./reports)

      .EXAMPLE
      Get-LocalAdminAudit -ComputerName localhost -OutputPath .\reports -Verbose

      .EXAMPLE
      Get-LocalAdminAudit -ComputerName SRV1,SRV2 -BaselinePath .\config\local-admin-allowlist.json -OutputPath .\reports
    #>
    [CmdletBinding()]
    param(
        [string[]]$ComputerName = @('localhost'),
        [System.Management.Automation.PSCredential]$Credential,
        [string]$BaselinePath,
        [string]$OutputPath = './reports'
    )

    begin {
        if ($OutputPath) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

        function Resolve-AllowList {
            param([string]$Path)
            if (-not $Path -or -not (Test-Path $Path)) { return @() }

            $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
            switch ($ext) {
                '.json' {
                    $json = Get-Content $Path -Raw | ConvertFrom-Json
                    $items = @()
                    if ($json -is [System.Collections.IEnumerable]) { $items = $json }
                    elseif ($json.Allowed) { $items = $json.Allowed }
                    $items | ForEach-Object {
                        if ($_ -is [string]) { $_ }
                        elseif ($_.Name) { $_.Name }
                    } | Where-Object { $_ } | Sort-Object -Unique
                }
                '.csv' {
                    Import-Csv $Path | ForEach-Object { $_.Name } | Where-Object { $_ } | Sort-Object -Unique
                }
                default { @() }
            }
        }

        $allow = Resolve-AllowList -Path $BaselinePath
        if ($allow.Count -gt 0) { Write-Verbose "Loaded allow-list entries: $($allow.Count)" }

        $sb = {
            param($allowList)

            function _GetLocalAdmins_GetLocalGroupMember {
                try {
                    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop | Out-Null
                    $members = Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop
                    foreach ($m in $members) {
                        # Normalize like 'DOMAIN\User' or 'BUILTIN\Administrators'
                        $normalized = if ($m.ObjectClass -eq 'Group' -and $m.Name -match '^.+\\.+') { $m.Name }
                        elseif ($m.Name -match '^.+\\.+') { $m.Name }
                        else { $m.Name }
                        [pscustomobject]@{
                            ComputerName = $env:COMPUTERNAME
                            Member       = $normalized
                            ObjectClass  = $m.ObjectClass
                            SID          = $m.SID.Value
                            Source       = 'LocalAccounts'
                            Note         = $null
                        }
                    }
                } catch { $null }
            }

            function _GetLocalAdmins_ADSI {
                try {
                    $grp = [ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group"
                    $e = $grp.psbase.Invoke('Members')
                    $out = foreach ($i in $e) {
                        $path = $i.GetType().InvokeMember('ADsPath', 'GetProperty', $null, $i, $null)
                        # ADsPath examples: WinNT://BUILTIN/Administrators or WinNT://CONTOSO/Server Admins
                        $name = $i.GetType().InvokeMember('Name', 'GetProperty', $null, $i, $null)
                        $class = $i.GetType().InvokeMember('Class', 'GetProperty', $null, $i, $null)
                        $domain = $null
                        if ($path -match 'WinNT://([^/]+)/') { $domain = $matches[1] }
                        $display = if ($domain) { "$domain\$name" } else { $name }
                        [pscustomobject]@{
                            ComputerName = $env:COMPUTERNAME
                            Member       = $display
                            ObjectClass  = $class
                            SID          = $null
                            Source       = 'ADSI'
                            Note         = $null
                        }
                    }
                    $out
                } catch { $null }
            }

            $rows = _GetLocalAdmins_GetLocalGroupMember
            if (-not $rows) { $rows = _GetLocalAdmins_ADSI }

            if (-not $rows) {
                [pscustomobject]@{
                    ComputerName = $env:COMPUTERNAME
                    Member       = $null
                    ObjectClass  = $null
                    SID          = $null
                    Source       = 'None'
                    Status       = 'Failed'
                    Reason       = 'Unable to enumerate Administrators (module/cmdlets unavailable?)'
                }
                return
            }

            # Apply allow-list if provided
            $rows | ForEach-Object {
                $name = $_.Member
                $status = if ($allowList -and $allowList.Count -gt 0) {
                    if ($allowList -contains $name) { 'Allowed' } else { 'Unexpected' }
                } else { 'Unscoped' }
                [pscustomobject]@{
                    ComputerName = $_.ComputerName
                    Member       = $name
                    ObjectClass  = $_.ObjectClass
                    SID          = $_.SID
                    Source       = $_.Source
                    Status       = $status
                    Reason       = $null
                }
            }
        }

        $results = New-Object System.Collections.Generic.List[object]
    }

    process {
        foreach ($cn in $ComputerName) {
            try {
                if ($cn -in @('localhost', '127.0.0.1', '::1', $env:COMPUTERNAME)) {
                    $r = & $sb $allow
                } else {
                    $icm = @{
                        ComputerName = $cn
                        ScriptBlock  = $sb
                        ArgumentList = @($allow)
                        ErrorAction  = 'Stop'
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) { $icm.Credential = $Credential }
                    $r = Invoke-Command @icm
                }
                if ($r) { [void]$results.AddRange($r) }
            } catch {
                [void]$results.Add([pscustomobject]@{
                        ComputerName = $cn
                        Member       = $null
                        ObjectClass  = $null
                        SID          = $null
                        Source       = 'Error'
                        Status       = 'Failed'
                        Reason       = $_.Exception.Message
                    })
            }
        }
    }

    end {
        $data = $results.ToArray()

        if ($OutputPath) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
            $csv = Join-Path $OutputPath "LocalAdmins-$stamp.csv"
            $html = Join-Path $OutputPath "LocalAdmins-$stamp.html"

            $data | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv

            $title = "Local Administrators Audit"
            $pre = "<h2>$title</h2><p>Generated: $(Get-Date)</p>" +
            "<p>Targets: $([string]::Join(', ', $ComputerName))</p>" +
            ($(if ($BaselinePath) { "<p>Baseline: $BaselinePath</p>" } else { '' }))

            $summary = $data | Group-Object ComputerName, Status | ForEach-Object {
                [pscustomobject]@{
                    ComputerName = $_.Group[0].ComputerName
                    Status       = $_.Group[0].Status
                    Count        = $_.Count
                }
            } | Sort-Object ComputerName, Status

            @(
                $pre
                "<h3>Summary</h3>"
                ($summary | ConvertTo-Html -Fragment)
                "<h3>Details</h3>"
                ($data | Sort-Object ComputerName, Status, Member |
                ConvertTo-Html -Fragment -Property ComputerName, Member, ObjectClass, SID, Status, Source, Reason)
            ) -join "`n" |
            ConvertTo-Html -Title $title |
            Out-File -Encoding UTF8 $html

            Write-Verbose "CSV:  $csv"
            Write-Verbose "HTML: $html"
        }

        $data
    }
}
