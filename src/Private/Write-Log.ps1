
function Write-Log {
    [CmdletBinding()]
    param(
        [ValidateSet('Debug','Info','Warn','Error')]
        [string]$Level = 'Info',
        [string]$Message,
        [hashtable]$Data
    )
    $entry = [PSCustomObject]@{
        ts      = (Get-Date).ToString('o')
        level   = $Level
        message = $Message
        data    = $Data
    }
    $dir = './logs/{0}' -f (Get-Date -Format 'yyyy-MM-dd')
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $entry | ConvertTo-Json -Depth 5 | Add-Content -Path (Join-Path $dir 'run.jsonl')
    if ($Level -eq 'Error') { Write-Error $Message } else { Write-Verbose ($Message) -Verbose }
}
