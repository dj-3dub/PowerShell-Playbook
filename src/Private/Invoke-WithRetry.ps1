
function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [int]$MaxAttempts = 5,
        [int]$BaseDelayMilliseconds = 250
    )
    for ($i=1; $i -le $MaxAttempts; $i++) {
        try {
            return & $ScriptBlock
        } catch {
            if ($i -eq $MaxAttempts) { throw }
            Start-Sleep -Milliseconds ([int]($BaseDelayMilliseconds * [math]::Pow(2,$i-1) + (Get-Random -Minimum 0 -Maximum 100)))
        }
    }
}
