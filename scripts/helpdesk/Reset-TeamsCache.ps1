<#
.SYNOPSIS
    Clears the Microsoft Teams cache for the current user (new Teams and classic Teams).

.DESCRIPTION
    Stops Teams, clears its cache folder, and optionally restarts it.

      New Teams (ms-teams.exe, MSIX package MSTeams_8wekyb3d8bbwe):
        %LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams

      Classic Teams (Teams.exe, retired 2025, still found on older builds):
        %APPDATA%\Microsoft\Teams

    Only cache/profile data is removed. Install folders (%LOCALAPPDATA%\Microsoft\Teams)
    and the Teams Meeting Add-in for Outlook are left alone. The user signs in again
    on next launch.

.PARAMETER Client
    Which client to reset: Auto (default: whichever is installed), New, Classic, or Both.

.PARAMETER Restart
    Start Teams again after clearing the cache.

.EXAMPLE
    .\Reset-TeamsCache.ps1 -WhatIf
    Show what would be stopped and removed without changing anything.

.EXAMPLE
    .\Reset-TeamsCache.ps1 -Restart -Verbose
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Auto', 'New', 'Classic', 'Both')]
    [string]$Client = 'Auto',

    [switch]$Restart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$clients = @(
    [pscustomobject]@{
        Name     = 'New'
        Process  = 'ms-teams'
        Cache    = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
        Detect   = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe'
        Launch   = { Start-Process 'ms-teams.exe' }
    }
    [pscustomobject]@{
        Name     = 'Classic'
        Process  = 'Teams'
        Cache    = Join-Path $env:APPDATA 'Microsoft\Teams'
        Detect   = Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\Update.exe'
        Launch   = { Start-Process (Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\Update.exe') -ArgumentList '--processStart "Teams.exe"' }
    }
)

$targets = switch ($Client) {
    'New'     { $clients | Where-Object Name -eq 'New' }
    'Classic' { $clients | Where-Object Name -eq 'Classic' }
    'Both'    { $clients }
    'Auto'    { $clients | Where-Object { (Test-Path $_.Detect) -or (Test-Path $_.Cache) } }
}

if (-not $targets) {
    Write-Warning 'No Teams installation found for the current user.'
    return
}

foreach ($t in @($targets)) {
    Write-Verbose "[$($t.Name) Teams] Stopping $($t.Process).exe"
    $procs = @(Get-Process -Name $t.Process -ErrorAction SilentlyContinue)
    if ($procs -and $PSCmdlet.ShouldProcess("$($t.Process).exe ($($procs.Count) process(es))", 'Stop process')) {
        $procs | Stop-Process -Force
        # Give file handles a moment to release before deleting.
        Start-Sleep -Seconds 2
    }

    if (Test-Path $t.Cache) {
        if ($PSCmdlet.ShouldProcess($t.Cache, 'Clear Teams cache')) {
            Get-ChildItem -Path $t.Cache -Force | Remove-Item -Recurse -Force -ErrorAction Continue
            Write-Host "[$($t.Name) Teams] Cache cleared: $($t.Cache)" -ForegroundColor Green
        }
    }
    else {
        Write-Verbose "[$($t.Name) Teams] No cache folder at $($t.Cache)"
    }

    if ($Restart -and (Test-Path $t.Detect) -and $PSCmdlet.ShouldProcess("$($t.Name) Teams", 'Start')) {
        & $t.Launch
    }
}
