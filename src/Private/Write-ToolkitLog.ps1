function Write-ToolkitLog {
    <#
        Structured run log: one compact JSON object per line (JSON Lines) in ./logs/<yyyy-MM-dd>/run.jsonl,
        so logs can be tailed, grepped, or shipped to a SIEM / log pipeline as-is.
        Errors are also written to the error stream; everything else goes to the verbose stream.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')]
        [string]$Level = 'Info',
        [string]$Message,
        [hashtable]$Data
    )
    $entry = [PSCustomObject]@{
        ts      = (Get-Date).ToString('o')
        level   = $Level
        host    = [Environment]::MachineName
        message = $Message
        data    = $Data
    }
    $dir = Join-Path (Join-Path (Get-Location) 'logs') (Get-Date -Format 'yyyy-MM-dd')
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $entry | ConvertTo-Json -Depth 5 -Compress | Add-Content -Path (Join-Path $dir 'run.jsonl') -Encoding UTF8

    switch ($Level) {
        'Error' { Write-Error $Message }
        'Warn'  { Write-Warning $Message }
        default { Write-Verbose $Message }
    }
}
