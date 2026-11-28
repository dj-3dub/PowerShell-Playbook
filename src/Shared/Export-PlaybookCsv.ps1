function Export-PlaybookCsv {
    <#
        Writes objects to a UTF-8 CSV without a #TYPE header on every PowerShell version:
        -NoTypeInformation is required on Windows PowerShell 5.1 and obsolete (warns) on PowerShell 7.
        Always writes, even when the caller runs with -WhatIf (reports are read-only output).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Path
    )
    begin { $items = New-Object System.Collections.Generic.List[object] }
    process { if ($null -ne $InputObject) { $items.Add($InputObject) } }
    end {
        $lines = if ($PSVersionTable.PSVersion.Major -lt 6) { $items | ConvertTo-Csv -NoTypeInformation } else { $items | ConvertTo-Csv }
        [IO.File]::WriteAllText($Path, (@($lines) -join [Environment]::NewLine), (New-Object Text.UTF8Encoding $true))
    }
}
