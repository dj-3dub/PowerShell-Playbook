#!/usr/bin/env bash
# Start-ReportServer.sh
# Serve your PowerShell-Automation-Toolkit reports with a pretty index.

set -euo pipefail

# --- Config / args ---
PORT="${1:-8080}"          # Usage: ./Start-ReportServer.sh [port]
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORTS_DIR="${SCRIPT_DIR}/reports"
if [[ ! -d "$REPORTS_DIR" ]]; then
  echo "Reports directory not found at: $REPORTS_DIR"
  echo "Create it with: mkdir -p \"$REPORTS_DIR\""
  exit 1
fi

# --- Find primary IP (best-effort) ---
if command -v hostname >/dev/null 2>&1; then
  IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
IP="${IP:-127.0.0.1}"

# --- Build a clean index.html (auto-refresh) ---
INDEX="${REPORTS_DIR}/index.html"
TMP="${INDEX}.tmp"

{
  echo "<!doctype html><html><head><meta charset='utf-8'/>"
  echo "<meta http-equiv='refresh' content='10'/>"
  echo "<title>PowerShell Automation Toolkit — Reports</title>"
  cat <<'CSS'
<style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;margin:32px;max-width:1000px}
h1{margin:0 0 8px}
.subtitle{color:#666;margin:0 0 24px}
table{border-collapse:collapse;width:100%}
th,td{border:1px solid #e3e3e3;padding:8px 10px;text-align:left}
th{background:#f7f7f7}
a{text-decoration:none}
a:hover{text-decoration:underline}
.time{white-space:nowrap}
.badge{display:inline-block;background:#eef6ff;border:1px solid #cfe1ff;color:#004085;padding:2px 6px;border-radius:6px;font-size:12px;margin-left:8px}
footer{color:#888;margin-top:20px;font-size:12px}
</style>
CSS
  echo "</head><body>"
  echo "<h1>PowerShell Automation Toolkit</h1>"
  echo "<p class='subtitle'>Report directory index (auto-refreshes every 10s)</p>"

  # Table header
  echo "<table><thead><tr><th>Report</th><th>Modified</th><th>Size</th></tr></thead><tbody>"

  # List *.html files sorted by mtime (newest first)
  # shellcheck disable=SC2012
  ls -1t "${REPORTS_DIR}"/*.html 2>/dev/null | while read -r f; do
    bn="$(basename "$f")"
    mtime="$(date -r "$f" '+%Y-%m-%d %H:%M:%S')"
    size="$(numfmt --to=iec --suffix=B --padding=4 "$(stat -c%s "$f")" 2>/dev/null || stat -c%s "$f")"
    # Add a small badge based on filename
    badge=""
    case "$bn" in
      *ConditionalAccess*) badge="<span class='badge'>Conditional Access</span>";;
      *ExchangeHygiene*)   badge="<span class='badge'>Exchange</span>";;
      *LocalAdmins*)       badge="<span class='badge'>Local Admins</span>";;
      *CertExpiry*)        badge="<span class='badge'>Certificates</span>";;
      *PatchCompliance*)   badge="<span class='badge'>Patch</span>";;
      *BitLocker*)         badge="<span class='badge'>BitLocker</span>";;
      *RoleFeature*)       badge="<span class='badge'>Roles/Features</span>";;
      *DiskTrend*)         badge="<span class='badge'>Disk</span>";;
    esac
    echo "<tr><td><a href='./$bn'>$bn</a> $badge</td><td class='time'>$mtime</td><td>$size</td></tr>"
  done

  echo "</tbody></table>"
  echo "<footer>Serving: ${REPORTS_DIR}</footer>"
  echo "</body></html>"
} >"$TMP" && mv "$TMP" "$INDEX"

echo "=== PowerShell Automation Toolkit Report Server ==="
echo "Serving: $REPORTS_DIR"
echo "Index:   http://$IP:$PORT/"
echo "Tip:     This page auto-refreshes every 10 seconds."
echo "Press Ctrl+C to stop."

# --- Start Python server (bind all interfaces) ---
cd "$REPORTS_DIR"
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found. On Debian/Ubuntu: sudo apt-get update && sudo apt-get install -y python3"
  exit 1
fi
python3 -m http.server "$PORT" --bind 0.0.0.0
