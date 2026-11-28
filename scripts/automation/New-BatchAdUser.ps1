<#
.SYNOPSIS
    Bulk-creates Active Directory users from a CSV file.

.DESCRIPTION
    Reads a CSV file of user definitions and creates AD accounts with
    standardized attributes and optional group membership.

    Supports:
    -WhatIf   = standard PowerShell dry-run
    -Offline  = "no AD" mode (no AD calls, just preview + report)
    -Server / -Credential for talking to a specific DC later.

.PARAMETER CsvPath
    Path to the CSV file. Columns supported:
    FirstName, LastName, SamAccountName, UserPrincipalName, OU,
    Department, Title, Groups, InitialPassword (optional, discouraged)

.PARAMETER DefaultPassword
    Optional SecureString used for every account that has no InitialPassword.
    If omitted, each account gets a unique random 16-character password,
    displayed once at the end of the run for secure handoff and never
    written to the report CSV.

.PARAMETER Enabled
    Whether to enable new accounts immediately. Defaults to $true.

.PARAMETER PasswordNeverExpires
    Whether the password should be set to never expire. Defaults to $false.
    When $false (the default), users must change their password at first logon.

.PARAMETER Server
    Optional domain controller to target (e.g. dc1.corp.local).

.PARAMETER Credential
    Optional credential to use when talking to AD.

.PARAMETER Offline
    When specified, no AD module is imported and no AD calls are made.
    Output is a "planned users" report only.

.EXAMPLE
    .\New-BatchAdUser.ps1 -CsvPath .\scripts\data\new-hires.csv -Offline -Verbose

.EXAMPLE
    .\New-BatchAdUser.ps1 -CsvPath .\scripts\data\new-hires.csv -Server dc1.corp.local -Verbose

#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [securestring]$DefaultPassword,

    [Parameter(Mandatory = $false)]
    [bool]$Enabled = $true,

    [Parameter(Mandatory = $false)]
    [bool]$PasswordNeverExpires = $false,

    [Parameter(Mandatory = $false)]
    [string]$Server,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [switch]$Offline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Temporary passwords generated this run (shown once at the end, never exported).
$script:IssuedPasswords = New-Object System.Collections.Generic.List[object]

function New-TemporaryPassword {
    <#
        Cryptographically random password that satisfies AD complexity rules:
        at least one upper, lower, digit and symbol. Ambiguous characters (0/O, 1/l/I) excluded.
    #>
    param([ValidateRange(12, 128)][int]$Length = 16)

    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ'
        'abcdefghijkmnopqrstuvwxyz'
        '23456789'
        '!@#$%^&*-_=+?'
    )
    $all = -join $sets
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $pick = {
            param([string]$From)
            $buf = New-Object byte[] 4
            $rng.GetBytes($buf)
            $From[[BitConverter]::ToUInt32($buf, 0) % $From.Length]
        }
        $chars = New-Object System.Collections.Generic.List[char]
        foreach ($set in $sets) { $chars.Add((& $pick $set)) }
        while ($chars.Count -lt $Length) { $chars.Add((& $pick $all)) }

        # Fisher-Yates shuffle so the guaranteed characters aren't always first
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $buf = New-Object byte[] 4
            $rng.GetBytes($buf)
            $j = [BitConverter]::ToUInt32($buf, 0) % ($i + 1)
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }
        return -join $chars
    }
    finally {
        $rng.Dispose()
    }
}

function Import-AdModule {
    param(
        [string]$Server,
        [System.Management.Automation.PSCredential]$Credential
    )

    if ($Offline) {
        Write-Verbose "Offline mode enabled: skipping ActiveDirectory module import."
        return
    }

    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        throw "ActiveDirectory module not found. Install RSAT or run from a DC/management server."
    }

    Import-Module ActiveDirectory -ErrorAction Stop

    Write-Verbose "Validating AD connectivity..."

    if ($Server) {
        Get-ADDomainController -Server $Server -Service ADWS -ErrorAction Stop | Out-Null
        Write-Verbose "ADWS reachable on server '$Server'."
    }
    else {
        Get-ADDomainController -Discover -Service ADWS -ErrorAction Stop | Out-Null
        Write-Verbose "Default ADWS-enabled domain controller discovered."
    }
}

function New-UserFromRow {
    # New-ADUser needs a SecureString. The plaintext comes from either the (discouraged, warned) CSV column
    # or a password this script just generated and must show once for handoff, so the conversion is inherent.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Converts a just-generated or operator-supplied initial password for New-ADUser.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Row
    )

    $givenName   = $Row.FirstName
    $surname     = $Row.LastName
    $sam         = $Row.SamAccountName
    $upn         = $Row.UserPrincipalName
    $ou          = $Row.OU
    $dept        = $Row.Department
    $title       = $Row.Title
    $csvPassword = if ($Row.PSObject.Properties['InitialPassword']) { $Row.InitialPassword } else { $null }
    $groups      = @()

    if ($Row.Groups) {
        $groups = $Row.Groups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    if (-not $sam) {
        throw "Row is missing SamAccountName. FirstName=$givenName LastName=$surname"
    }

    if (-not $ou) {
        throw "Row for $sam is missing OU."
    }

    $name = "$givenName $surname".Trim()
    if (-not $name) { $name = $sam }

    $result = [pscustomobject]@{
        SamAccountName = $sam
        Name           = $name
        OU             = $ou
        Department     = $dept
        Title          = $title
        Groups         = ($groups -join ';')
        Enabled        = $Enabled
        Offline        = [bool]$Offline
        Created        = $false
        Error          = $null
    }

    if ($Offline) {
        Write-Verbose "OFFLINE: would create AD user '$sam' in '$ou' (Groups: $($result.Groups))."
        return $result
    }

    # Online mode - real AD calls
    $generatedPassword = $null
    if ($csvPassword) {
        Write-Warning "Using plaintext InitialPassword from CSV for '$sam'. Prefer omitting it so a random password is generated."
        $securePassword = ConvertTo-SecureString -String $csvPassword -AsPlainText -Force
    }
    elseif ($DefaultPassword) {
        $securePassword = $DefaultPassword
    }
    else {
        $generatedPassword = New-TemporaryPassword
        $securePassword    = ConvertTo-SecureString -String $generatedPassword -AsPlainText -Force
    }

    $newUserParams = @{
        Name               = $name
        GivenName          = $givenName
        Surname            = $surname
        SamAccountName     = $sam
        UserPrincipalName  = $upn
        Enabled            = $Enabled
        AccountPassword    = $securePassword
        # AD rejects ChangePasswordAtLogon together with PasswordNeverExpires.
        ChangePasswordAtLogon = (-not $PasswordNeverExpires)
        Path               = $ou
        Department         = $dept
        Title              = $title
        ErrorAction        = 'Stop'
    }

    if ($Server)     { $newUserParams.Server     = $Server }
    if ($Credential) { $newUserParams.Credential = $Credential }

    if ($PSCmdlet.ShouldProcess("AD user '$sam' in '$ou'", "Create")) {
        Write-Verbose "Creating AD user '$sam' in '$ou'..."
        New-ADUser @newUserParams

        if ($PasswordNeverExpires) {
            $setParams = @{
                Identity    = $sam
                ErrorAction = 'Stop'
            }
            if ($Server)     { $setParams.Server     = $Server }
            if ($Credential) { $setParams.Credential = $Credential }

            Set-ADUser @setParams -PasswordNeverExpires $true
        }

        if ($groups.Count -gt 0) {
            foreach ($group in $groups) {
                try {
                    Write-Verbose "Adding '$sam' to group '$group'..."
                    $addParams = @{
                        Identity    = $group
                        Members     = $sam
                        ErrorAction = 'Stop'
                    }
                    if ($Server)     { $addParams.Server     = $Server }
                    if ($Credential) { $addParams.Credential = $Credential }

                    Add-ADGroupMember @addParams
                }
                catch {
                    Write-Warning "Failed to add '$sam' to group '$group': $_"
                    $result.Error = "Group add failed: $group"
                }
            }
        }

        $result.Created = $true
        if ($generatedPassword) {
            $script:IssuedPasswords.Add([pscustomobject]@{ SamAccountName = $sam; TemporaryPassword = $generatedPassword })
        }
    }

    return $result
}

try {
    Import-AdModule -Server $Server -Credential $Credential

    Write-Verbose "Importing CSV from '$CsvPath'..."
    $rows = @(Import-Csv -Path $CsvPath)

    if (-not $rows -or $rows.Count -eq 0) {
        throw "CSV '$CsvPath' contains no rows."
    }

    $results = foreach ($row in $rows) {
        try {
            New-UserFromRow -Row $row
        }
        catch {
            Write-Warning "Error creating user from row '$($row.SamAccountName)': $_"
            [pscustomobject]@{
                SamAccountName = $row.SamAccountName
                Name           = "$($row.FirstName) $($row.LastName)".Trim()
                OU             = $row.OU
                Department     = $row.Department
                Title          = $row.Title
                Groups         = $row.Groups
                Enabled        = $Enabled
                Offline        = [bool]$Offline
                Created        = $false
                Error          = $_.Exception.Message
            }
        }
    }

    if ($results) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $outDir    = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'exports'
        $null      = New-Item -Path $outDir -ItemType Directory -Force -ErrorAction SilentlyContinue
        $report    = Join-Path -Path $outDir -ChildPath "New-BatchAdUser-$timestamp.csv"

        $results | Export-Csv -Path $report -NoTypeInformation -Encoding UTF8
        Write-Host "Processed $($results.Count) user(s). Report: $report" -ForegroundColor Green

        if ($Offline) {
            Write-Host "Offline mode: no changes were made to Active Directory." -ForegroundColor Yellow
        }

        if ($script:IssuedPasswords.Count -gt 0) {
            Write-Host ''
            Write-Host 'Temporary passwords (shown once, not saved; users must change at first logon).' -ForegroundColor Yellow
            Write-Host 'Hand these off through your secure channel, then clear the console.' -ForegroundColor Yellow
            $script:IssuedPasswords | Format-Table -AutoSize | Out-Host
        }
    }
    else {
        Write-Host "No rows were processed." -ForegroundColor Yellow
    }
}
catch {
    Write-Error $_
    exit 1
}
