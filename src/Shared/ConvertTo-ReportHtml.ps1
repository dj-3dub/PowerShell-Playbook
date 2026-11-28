function ConvertTo-ReportHtml {
    <#
        The one HTML report builder for both PowerShell Playbook modules (dot-sourced by each .psm1).

        Produces: title, generated-by line, metadata chips, a status summary, optional extra sections, and a
        table whose Status cells are colour-coded. All values are HTML-encoded. Reports keep their own status
        words; they are mapped to four colours here so every report reads the same way.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][AllowEmptyCollection()]$Data,
        [System.Collections.IDictionary]$Meta,
        # Extra sections rendered above the main table, as @{ 'Heading' = $objects }.
        [System.Collections.IDictionary]$Section,
        # Columns (and order) for the main table. Default: all properties.
        [string[]]$Property = '*'
    )

    $classOf = [ordered]@{
        ok   = 'OK', 'Done', 'Compliant', 'Allowed', 'Success', 'Restored', 'Removed'
        warn = 'Warn', 'Stale', 'Skipped', 'Planned', 'Expiring'
        fail = 'Fail', 'Failed', 'NonCompliant', 'Unexpected', 'Expired'
    }
    $cssClass = {
        param([string]$Status)
        foreach ($k in $classOf.Keys) { if ($classOf[$k] -contains $Status) { return $k } }
        'info'
    }
    $severity = @{ ok = 0; warn = 1; fail = 2; info = 3 }
    $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }

    $colourStatus = {
        param([string]$Html, [object[]]$Rows)
        if (-not $Rows.Count -or -not $Rows[0].PSObject.Properties['Status']) { return $Html }
        foreach ($s in @($Rows | ForEach-Object { [string]$_.Status } | Where-Object { $_ } | Sort-Object -Unique)) {
            $e = & $enc $s
            $Html = $Html.Replace("<td>$e</td>", "<td class=""status $(& $cssClass $s)"">$e</td>")
        }
        $Html
    }
    $table = {
        param([object[]]$Rows, [string[]]$Columns)
        if (-not $Rows.Count) { return "<p class='subtle'>No rows.</p>" }
        & $colourStatus (($Rows | ConvertTo-Html -Property $Columns -Fragment) -join "`n") $Rows
    }

    $rows = @($Data)

    $metaHtml = ''
    if ($Meta) {
        $metaHtml = ($Meta.GetEnumerator() | ForEach-Object {
                "<span class='chip'><b>$(& $enc $_.Key):</b> $(& $enc $_.Value)</span>"
            }) -join "`n"
    }

    $summaryHtml = ''
    if ($rows.Count -and $rows[0].PSObject.Properties['Status']) {
        $summaryHtml = ($rows | Group-Object { [string]$_.Status } |
                Sort-Object { $severity[(& $cssClass $_.Name)] }, Name |
                ForEach-Object { "<span class='chip $(& $cssClass $_.Name)'>$(& $enc $_.Name): $($_.Count)</span>" }) -join "`n"
    }

    $sectionsHtml = ''
    if ($Section) {
        $sectionsHtml = ($Section.GetEnumerator() | ForEach-Object {
                "<h2>$(& $enc $_.Key)</h2>`n" + (& $table @($_.Value) @('*'))
            }) -join "`n"
        $sectionsHtml += "`n<h2>Details</h2>"
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
  h2 { font-size: 15px; margin: 24px 0 0; }
  .subtle { color: var(--muted); font-size: 12px; }
  .chips { margin: 14px 0 6px; }
  .chip { display: inline-block; padding: 4px 10px; margin: 0 6px 6px 0; border: 1px solid var(--line); border-radius: 999px; font-size: 12px; }
  .chip b { font-weight: 600; }
  .chip.ok   { color: var(--ok);   background: var(--ok-bg);   border-color: transparent; }
  .chip.warn { color: var(--warn); background: var(--warn-bg); border-color: transparent; }
  .chip.fail { color: var(--fail); background: var(--fail-bg); border-color: transparent; }
  .chip.info { color: var(--info); background: var(--info-bg); border-color: transparent; }
  table { border-collapse: collapse; width: 100%; margin-top: 12px; font-size: 13px; }
  th, td { border-bottom: 1px solid var(--line); padding: 8px 10px; text-align: left; vertical-align: top; }
  th { background: var(--head); font-weight: 600; border-top: 1px solid var(--line); }
  tr:hover td { background: #fafbfc; }
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
$sectionsHtml
$(& $table $rows $Property)
<div class="footer">PowerShell Playbook &middot; github.com/dj-3dub/PowerShell-Playbook</div>
</body>
</html>
"@
}
