function New-RandomPassword {
    <#
        Cryptographically random password meeting AD complexity (upper, lower, digit, symbol).
        Ambiguous characters (0/O, 1/l/I) are excluded so a password read aloud or retyped survives.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([ValidateRange(12, 128)][int]$Length = 20)

    $sets = 'ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#$%^&*-_=+?'
    $all  = -join $sets
    $rng  = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $next = {
            param([int]$Max)
            $buf = New-Object byte[] 4
            $rng.GetBytes($buf)
            [BitConverter]::ToUInt32($buf, 0) % $Max
        }
        $chars = New-Object System.Collections.Generic.List[char]
        foreach ($set in $sets) { $chars.Add($set[(& $next $set.Length)]) }
        while ($chars.Count -lt $Length) { $chars.Add($all[(& $next $all.Length)]) }
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $j = & $next ($i + 1)
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }
        -join $chars
    }
    finally {
        $rng.Dispose()
    }
}
