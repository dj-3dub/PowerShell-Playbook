<#
.SYNOPSIS
    Creates or updates Intune Remediations (detection + remediation script pairs) from folders in this directory.

.DESCRIPTION
    For each folder containing Detect.ps1, Remediate.ps1 and remediation.json, the scripts are base64-encoded
    and sent to Microsoft Graph (beta) /deviceManagement/deviceHealthScripts. An existing remediation with the
    same display name is updated in place, so re-running is safe. Optionally assigns it to an Entra group with a
    daily schedule.

    Requires Microsoft.Graph.Authentication and:
        Connect-MgGraph -Scopes DeviceManagementConfiguration.ReadWrite.All

.PARAMETER Path
    One or more remediation folders. Default: every folder next to this script that contains a remediation.json.

.PARAMETER AssignToGroupId
    Entra group object ID to assign the remediation(s) to, running daily at -DailyTime.

.PARAMETER DailyTime
    Local time for the daily schedule when assigning. Default 09:00.

.EXAMPLE
    .\Publish-IntuneRemediation.ps1 -WhatIf

.EXAMPLE
    .\Publish-IntuneRemediation.ps1 -Path .\TimeSync -AssignToGroupId 1b2c3d4e-0000-0000-0000-000000000000
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Path,
    [ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$AssignToGroupId,
    [ValidatePattern('^\d{2}:\d{2}$')][string]$DailyTime = '09:00'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
    throw 'Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
}
if (-not (Get-MgContext)) {
    throw 'Run Connect-MgGraph -Scopes DeviceManagementConfiguration.ReadWrite.All first.'
}

$base = 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'
if (-not $Path) {
    $Path = Get-ChildItem -Path $PSScriptRoot -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'remediation.json') } |
        Select-Object -ExpandProperty FullName
}

# Existing remediations, matched by display name for idempotent updates.
$existing = @{}
$uri = "$base`?`$select=id,displayName"
while ($uri) {
    $page = Invoke-MgGraphRequest -Method GET -Uri $uri
    foreach ($item in $page.value) { $existing[$item.displayName] = $item.id }
    $uri = $page['@odata.nextLink']
}

$toBase64 = { param($file) [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $file).ProviderPath)) }

foreach ($folder in $Path) {
    $meta = Get-Content (Join-Path $folder 'remediation.json') -Raw | ConvertFrom-Json
    $body = @{
        '@odata.type'            = '#microsoft.graph.deviceHealthScript'
        displayName              = $meta.displayName
        description              = $meta.description
        publisher                = 'PowerShell Playbook'
        runAsAccount             = $meta.runAsAccount
        runAs32Bit               = [bool]$meta.runAs32Bit
        enforceSignatureCheck    = $false
        detectionScriptContent   = & $toBase64 (Join-Path $folder 'Detect.ps1')
        remediationScriptContent = & $toBase64 (Join-Path $folder 'Remediate.ps1')
        roleScopeTagIds          = @('0')
    }

    $id = $existing[$meta.displayName]
    $action = if ($id) { 'Update' } else { 'Create' }
    if (-not $PSCmdlet.ShouldProcess($meta.displayName, "$action Intune remediation")) {
        [pscustomobject]@{ Name = $meta.displayName; Id = $id; Action = "$action (WhatIf)" }
        continue
    }

    if ($id) {
        Invoke-MgGraphRequest -Method PATCH -Uri "$base/$id" -Body ($body | ConvertTo-Json -Depth 5) -ContentType 'application/json' | Out-Null
    }
    else {
        $id = (Invoke-MgGraphRequest -Method POST -Uri $base -Body ($body | ConvertTo-Json -Depth 5) -ContentType 'application/json').id
    }

    if ($AssignToGroupId) {
        $assign = @{
            deviceHealthScriptAssignments = @(@{
                    target               = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $AssignToGroupId }
                    runRemediationScript = $true
                    runSchedule          = @{ '@odata.type' = '#microsoft.graph.deviceHealthScriptDailySchedule'; interval = 1; useUtc = $false; time = "$DailyTime`:00" }
                })
        }
        Invoke-MgGraphRequest -Method POST -Uri "$base/$id/assign" -Body ($assign | ConvertTo-Json -Depth 6) -ContentType 'application/json' | Out-Null
    }

    [pscustomobject]@{ Name = $meta.displayName; Id = $id; Action = "${action}d" }
}
