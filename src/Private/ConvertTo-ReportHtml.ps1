
    function ConvertTo-ReportHtml {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Title,
            [Parameter(Mandatory)]$Data
        )
        $rows = $Data | ConvertTo-Html -Property * -Fragment
        @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>$Title</title>
<style>
body { font-family: Segoe UI, Roboto, Arial, sans-serif; margin: 24px; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ddd; padding: 8px; }
th { background: #f4f4f4; text-align: left; }
h1 { margin-top: 0; }
</style>
</head>
<body>
<h1>$Title</h1>
$rows
</body>
</html>
"@
    }
