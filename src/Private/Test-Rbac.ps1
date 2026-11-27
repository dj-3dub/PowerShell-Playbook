function Test-Rbac {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Area,
        $Config
    )

    $hasConfig = $null -ne $Config
    Write-ToolkitLog -Level Info -Message "RBAC check (mock)" -Data @{
        Area      = $Area
        HasConfig = $hasConfig
    }
    return $true
}
