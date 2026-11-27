<#
.SYNOPSIS
    Checks mailbox capacity and retention configuration.

.DESCRIPTION
    For one or more mailboxes, this script:
      - Retrieves mailbox size, quotas, and storage limit status
      - Calculates % used of ProhibitSendQuota (or IssueWarningQuota if ProhibitSend not set)
      - Inspects the assigned retention policy and its tags
      - Flags whether a "MoveToArchive" tag with AgeLimitForRetention <= 365 days exists
      - Optionally exports a CSV report

    Useful for tickets like:
      - "Mailbox at 100GB capacity"
      - "Is this user on the correct retention policy?"
      - "Should email older than 1 year be auto-archived?"

.PARAMETER Identity
    One or more mailbox identities (UPN, alias, or display name).
    If omitted and -AllMailboxes is not used, you will be prompted.

.PARAMETER AllMailboxes
    If specified, runs against all user mailboxes.

.PARAMETER WarningThresholdPercent
    Threshold (in %) of quota at which to flag a mailbox as "NearCapacity".
    Default is 90.

.PARAMETER ExportCsv
    If specified, exports results to a CSV under exports\Mailboxes.

.PARAMETER OutputPath
    Optional explicit CSV path. If not supplied and -ExportCsv is used,
    the report is written to exports\Mailboxes\Test-MailboxCapacity-<timestamp>.csv
    under the repo root.

.EXAMPLE
    # Single mailbox
    .\Test-MailboxCapacityAndRetention.ps1 -Identity user@contoso.com -Verbose

.EXAMPLE
    # All mailboxes, export CSV
    .\Test-MailboxCapacityAndRetention.ps1 -AllMailboxes -ExportCsv

.NOTES
    Requires Exchange cmdlets:
      - Preferably: Get-EXOMailbox, Get-EXOMailboxStatistics (EXO V2)
      - Or:        Get-Mailbox, Get-MailboxStatistics (on-prem / older EXO)

    Run Connect-ExchangeOnline (or open Exchange Management Shell) before using.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [string[]]$Identity,

    [Parameter(Mandatory = $false)]
    [switch]$AllMailboxes,

    [Parameter(Mandatory = $false)]
    [int]$WarningThresholdPercent = 90,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCsv,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Detect Exchange cmdlets
    $exoMailboxCmd  = Get-Command -Name Get-EXOMailbox -ErrorAction SilentlyContinue
    $exoStatsCmd    = Get-Command -Name Get-EXOMailboxStatistics -ErrorAction SilentlyContinue
    $legacyMailbox  = Get-Command -Name Get-Mailbox -ErrorAction SilentlyContinue
    $legacyStats    = Get-Command -Name Get-MailboxStatistics -ErrorAction SilentlyContinue

    if (-not $exoMailboxCmd -and -not $legacyMailbox) {
        throw "No Exchange mailbox cmdlets found. Connect to Exchange Online or open an Exchange Management Shell first."
    }

    # Get-EXOMailbox returns a minimal property set unless these are requested explicitly.
    $mailboxProps = 'ProhibitSendQuota', 'IssueWarningQuota', 'RetentionPolicy', 'ArchiveStatus', 'ArchiveDatabase'

    function Get-MailboxWrapper {
        param(
            [Parameter(Mandatory = $false)][string[]]$Id,
            [Parameter(Mandatory = $false)][switch]$All
        )

        if ($exoMailboxCmd) {
            if ($All) {
                return Get-EXOMailbox -ResultSize Unlimited -Properties $mailboxProps
            }
            elseif ($Id) {
                $all = @()
                foreach ($i in $Id) {
                    $all += Get-EXOMailbox -Identity $i -Properties $mailboxProps
                }
                return $all
            }
        }
        else {
            if ($All) {
                return Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox
            }
            elseif ($Id) {
                $all = @()
                foreach ($i in $Id) {
                    $all += Get-Mailbox -Identity $i
                }
                return $all
            }
        }
    }

    function Get-MailboxStatsWrapper {
        param(
            [Parameter(Mandatory = $true)][string]$Identity
        )

        if ($exoStatsCmd) {
            return Get-EXOMailboxStatistics -Identity $Identity
        }
        elseif ($legacyStats) {
            return Get-MailboxStatistics -Identity $Identity
        }
        else {
            throw "No mailbox statistics cmdlets available."
        }
    }

    function Convert-ToGB {
        param(
            [Parameter(Mandatory = $true)]
            [AllowNull()]
            $Value
        )

        if ($null -eq $Value) { return $null }

        # Live ByteQuantifiedSize (Exchange Management Shell / EXO V2 with types loaded)
        if ($Value.PSObject.Methods['ToBytes']) {
            return [Math]::Round(($Value.ToBytes() / 1GB), 2)
        }

        # Deserialized/string form, e.g. "99.13 GB (106,443,612,160 bytes)": use the exact byte count
        $text = [string]$Value
        if ($text -match '\(([\d,\.\s]+)\s*bytes\)') {
            $bytes = [double]($matches[1] -replace '[^\d]', '')
            return [Math]::Round(($bytes / 1GB), 2)
        }

        # Plain number of bytes
        $number = 0.0
        if ([double]::TryParse($text, [ref]$number)) {
            return [Math]::Round(($number / 1GB), 2)
        }

        return $null
    }

    function Get-RetentionDetails {
        param(
            [string]$PolicyName
        )

        $result = [pscustomobject]@{
            RetentionPolicy         = $PolicyName
            RetentionTags           = $null
            HasOneYearArchivePolicy = $false
        }

        if (-not $PolicyName) {
            return $result
        }

        $policyCmd = Get-Command -Name Get-RetentionPolicy -ErrorAction SilentlyContinue
        $tagCmd    = Get-Command -Name Get-RetentionPolicyTag -ErrorAction SilentlyContinue

        if (-not $policyCmd -or -not $tagCmd) {
            return $result
        }

        try {
            $policy = Get-RetentionPolicy -Identity $PolicyName -ErrorAction Stop
        }
        catch {
            return $result
        }

        $tags = @()

        foreach ($link in $policy.RetentionPolicyTagLinks) {
            try {
                $tags += Get-RetentionPolicyTag -Identity $link -ErrorAction SilentlyContinue
            }
            catch { }
        }

        if ($tags.Count -gt 0) {
            $result.RetentionTags = ($tags | Select-Object -ExpandProperty Name | Sort-Object -Unique) -join '; '

            # Check for MoveToArchive tag with AgeLimitForRetention <= 365 days
            $moveTags = $tags | Where-Object {
                $_.RetentionAction -eq 'MoveToArchive' -and $_.AgeLimitForRetention
            }

            foreach ($t in $moveTags) {
                # AgeLimitForRetention is a TimeSpan
                try {
                    if ($t.AgeLimitForRetention.Days -le 365) {
                        $result.HasOneYearArchivePolicy = $true
                        break
                    }
                }
                catch { }
            }
        }

        return $result
    }

    # repo root + export folder (for CSV)
    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $exportRoot = Join-Path (Join-Path $repoRoot 'exports') 'Mailboxes'
    $null = New-Item -Path $exportRoot -ItemType Directory -Force -ErrorAction SilentlyContinue

    $script:results = New-Object System.Collections.Generic.List[object]
}

process {
    if (-not $AllMailboxes -and -not $Identity) {
        $inputId = Read-Host "Enter mailbox identity (UPN/alias). For multiple, separate with commas"
        if (-not [string]::IsNullOrWhiteSpace($inputId)) {
            $Identity = $inputId.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }
    }

    $mailboxes = Get-MailboxWrapper -Id $Identity -All:$AllMailboxes

    if (-not $mailboxes) {
        Write-Warning "No mailboxes found for the given parameters."
        return
    }

    foreach ($mbx in $mailboxes) {
        # PowerShell 5.1-compatible (no '??' operator)
        $mbxId = if ($mbx.UserPrincipalName) { $mbx.UserPrincipalName } else { [string]$mbx.PrimarySmtpAddress }
        Write-Verbose "Processing mailbox: $mbxId"

        $stats = $null
        try {
            $stats = Get-MailboxStatsWrapper -Identity $mbxId
        }
        catch {
            Write-Warning "Failed to get statistics for ${mbxId}: $_"
        }

        # Size / quota calculations
        $totalSizeGB = $null
        $quotaGB     = $null
        $percentUsed = $null

        if ($stats) {
            $totalSizeGB = Convert-ToGB -Value $stats.TotalItemSize
        }

        # Use ProhibitSendQuota as primary limit, fallback to IssueWarningQuota
        $quotaSource = $null
        if ($mbx.ProhibitSendQuota -and [string]$mbx.ProhibitSendQuota -ne 'Unlimited') {
            $quotaGB     = Convert-ToGB -Value $mbx.ProhibitSendQuota
            $quotaSource = 'ProhibitSendQuota'
        }
        elseif ($mbx.IssueWarningQuota -and [string]$mbx.IssueWarningQuota -ne 'Unlimited') {
            $quotaGB     = Convert-ToGB -Value $mbx.IssueWarningQuota
            $quotaSource = 'IssueWarningQuota'
        }

        if ($quotaGB -and $null -ne $totalSizeGB -and $quotaGB -gt 0) {
            $percentUsed = [Math]::Round(($totalSizeGB / $quotaGB) * 100, 2)
        }

        $nearCapacity = ($null -ne $percentUsed -and $percentUsed -ge $WarningThresholdPercent)

        # Retention
        $retentionInfo = Get-RetentionDetails -PolicyName ([string]$mbx.RetentionPolicy)

        # Archive
        $archiveEnabled = ([string]$mbx.ArchiveStatus -eq 'Active') -or [bool]$mbx.ArchiveDatabase

        $row = [pscustomobject]@{
            Mailbox                 = $mbxId
            TotalSizeGB             = $totalSizeGB
            QuotaGB                 = $quotaGB
            QuotaSource             = $quotaSource
            PercentUsed             = $percentUsed
            NearCapacity            = $nearCapacity
            ArchiveEnabled          = $archiveEnabled
            RetentionPolicy         = $retentionInfo.RetentionPolicy
            RetentionTags           = $retentionInfo.RetentionTags
            HasOneYearArchivePolicy = $retentionInfo.HasOneYearArchivePolicy
            Recommendation          = if ($nearCapacity -and -not $archiveEnabled) {
                                          'Near quota with no archive: enable archive mailbox and a MoveToArchive policy'
                                      } elseif ($nearCapacity -and -not $retentionInfo.HasOneYearArchivePolicy) {
                                          'Near quota: assign a MoveToArchive retention tag (<= 1 year)'
                                      } elseif ($nearCapacity) {
                                          'Near quota: archive policy present; check archive processing (Start-ManagedFolderAssistant)'
                                      } else { 'OK' }
        }

        $script:results.Add($row)
        $row
    }
}

end {
    if (($ExportCsv -or $OutputPath) -and $script:results.Count -gt 0) {
        $csvPath = if ($OutputPath) { $OutputPath } else {
            Join-Path $exportRoot ('Test-MailboxCapacity-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        }
        $script:results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Report exported to: $csvPath" -ForegroundColor Green
    }
}
