function Get-EotConfig {
    [CmdletBinding()]
    param(
        [ValidateSet('Dev','Test','Prod')]
        [string]$Environment = 'Dev'
    )
    # This file lives in src/Private; module config ships in src/config.
    $configDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'config'
    $wanted    = '{0}.json' -f $Environment

    # Match case-insensitively so 'Dev.json' resolves on Linux/macOS as well as Windows.
    $file = Get-ChildItem -Path $configDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq $wanted } |
        Select-Object -First 1 -ExpandProperty FullName

    if (-not $file) {
        throw "Config not found: $wanted in $configDir"
    }
    try {
        return Get-Content -Path $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to read/parse config file: $file. $_"
    }
}
