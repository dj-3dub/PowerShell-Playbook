function ConvertTo-ReportHtml {
    <#
        Shared HTML report body for the PowerShellPlaybook module: title, optional metadata chips,
        a status summary, and a table with colour-coded Status cells. Values are HTML-encoded.
        Status words are mapped to four colours so different reports can keep their own vocabulary.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][AllowEmptyCollection()]$Data,
        [System.Collections.IDictionary]$Meta
    )

    $classOf = @{
        ok   = 'OK', 'Done', 'Compliant', 'Allowed', 'Success', 'Restored'
        warn = 'Warn', 'Stale', 'Skipped', 'Unexpected', 'Planned'
        fail = 'Fail', 'Failed', 'NonCompliant'
    }
    $cssClass = {
        param([string]$Status)
        foreach ($k in $classOf.Keys) { if ($classOf[$k] -contains $Status) { return $k } }
        'info'
    }
    $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }

    $rows = @($Data)

    $metaHtml = ''
    if ($Meta) {
        $metaHtml = ($Meta.GetEnumerator() | ForEach-Object {
                "<span class='chip'><b>$(& $enc $_.Key):</b> $(& $enc $_.Value)</span>"
            }) -join "`n"
    }

    $summaryHtml = ''
    if ($rows.Count -and $rows[0].PSObject.Properties['Status']) {
        $summaryHtml = ($rows | Group-Object Status | ForEach-Object {
                "<span class='chip $(& $cssClass $_.Name)'>$(& $enc $_.Name): $($_.Count)</span>"
            }) -join "`n"
    }

    $table = ($rows | ConvertTo-Html -Property * -Fragment) -join "`n"
    if ($rows.Count -and $rows[0].PSObject.Properties['Status']) {
        $statuses = @($rows | ForEach-Object { [string]$_.Status } | Sort-Object -Unique | Where-Object { $_ })
        foreach ($s in $statuses) {
            $e = & $enc $s
            $table = $table.Replace("<td>$e</td>", "<td class=""status $(& $cssClass $s)"">$e</td>")
        }
    }

    $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
    @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>$(& $enc $Title)</title>
<style>
  :root { --fg:#1f2328; --muted:#656d76; --line:#d0d7de; --head:#f6f8fa;
          --ok:#1a7f37; --ok-bg:#dafbe1; --warn:#9a6700; --warn-bg:#fff8c5;
          --fail:#cf222e; --fail-bg:#ffebe9; --info:#0969da; --info-bg:#ddf4ff; }
  body { font-family: "Segoe UI", system-ui, -apple-system, Roboto, Arial, sans-serif; color: var(--fg); margin: 32px; }
  h1 { font-size: 22px; margin: 0 0 4px; }
  .subtle { color: var(--muted); font-size: 12px; }
  .chips { margin: 14px 0 6px; }
  .chip { display: inline-block; padding: 4px 10px; margin: 0 6px 6px 0; border: 1px solid var(--line); border-radius: 999px; font-size: 12px; }
  .chip.ok   { color: var(--ok);   background: var(--ok-bg);   border-color: transparent; }
  .chip.warn { color: var(--warn); background: var(--warn-bg); border-color: transparent; }
  .chip.fail { color: var(--fail); background: var(--fail-bg); border-color: transparent; }
  .chip.info { color: var(--info); background: var(--info-bg); border-color: transparent; }
  table { border-collapse: collapse; width: 100%; margin-top: 12px; font-size: 13px; }
  th, td { border-bottom: 1px solid var(--line); padding: 8px 10px; text-align: left; vertical-align: top; }
  th { background: var(--head); font-weight: 600; border-top: 1px solid var(--line); }
  td.status { font-weight: 600; white-space: nowrap; }
  td.ok { color: var(--ok); } td.warn { color: var(--warn); } td.fail { color: var(--fail); } td.info { color: var(--info); }
  .footer { margin-top: 24px; font-size: 12px; color: var(--muted); }
</style>
</head>
<body>
<h1>$(& $enc $Title)</h1>
<div class="subtle">Generated $generated on $(& $enc ([Environment]::MachineName))</div>
<div class="chips">$metaHtml</div>
<div class="chips">$summaryHtml</div>
$table
<div class="footer">PowerShell Playbook &middot; github.com/dj-3dub/PowerShell-Playbook</div>
</body>
</html>
"@
}
