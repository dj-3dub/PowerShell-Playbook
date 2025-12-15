<#
.SYNOPSIS
    Creates a support bundle tied to a helpdesk ticket ID.

.DESCRIPTION
    Wraps Collect-SupportBundle.ps1 (from this repo) and:
      - Prompts for (or accepts) a TicketId
      - Uses the current computer name by default
      - Outputs a ZIP with a consistent naming convention:
        SupportBundle_<TicketId>_<ComputerName>_<yyyyMMdd-HHmmss>.zip

.PARAMETER TicketId
    The ticket number or ID from your ITSM system.

.PARAMETER ComputerName
    Target computer. Defaults to the local machine.

.PARAMETER OutputRoot
    Root output directory. Defaults to .\out\SupportBundles relative to repo root.

.EXAMPLE
    .\New-HelpdeskTicketBundle.ps1 -TicketId INC123456

.EXAMPLE
    .\New-HelpdeskTicketBundle.ps1 -TicketId SR-1001 -ComputerName USERPC01 -Verbose
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TicketId,

    [Parameter(Mandatory = $false)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $TicketId) {
    $TicketId = Read-Host -Prompt 'Enter Helpdesk Ticket ID'
}

if (-not $TicketId) {
    throw "TicketId is required."
}

if (-not $OutputRoot) {
    # repo root relative to this script: scripts/automation -> repo
    $repoRoot   = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $OutputRoot = Join-Path $repoRoot 'out\SupportBundles'
}

$null = New-Item -Path $OutputRoot -ItemType Directory -Force -ErrorAction SilentlyContinue

$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$bundleName = "SupportBundle_{0}_{1}_{2}.zip" -f $TicketId, $ComputerName, $timestamp
$bundlePath = Join-Path $OutputRoot $bundleName

$collectScript = Join-Path $PSScriptRoot 'Collect-SupportBundle.ps1'

if (-not (Test-Path $collectScript)) {
    throw "Collect-SupportBundle.ps1 not found at '$collectScript'. Make sure it exists in scripts\automation."
}

Write-Verbose "TicketId: $TicketId"
Write-Verbose "Computer: $ComputerName"
Write-Verbose "Output:   $bundlePath"

# Assuming Collect-SupportBundle.ps1 supports -ComputerName and -OutputPath
& $collectScript -ComputerName $ComputerName -OutputPath $bundlePath

Write-Host "Support bundle created: $bundlePath" -ForegroundColor Green
