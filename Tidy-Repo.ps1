<# 
.SYNOPSIS
Tidy the repo: move helper scripts under scripts/, clean artifacts, and update .gitignore.

.PARAMETER DryRun
Show what would happen without changing anything.

.PARAMETER AutoCommit
Stage and commit changes automatically (requires git).

.EXAMPLE
.\Tidy-Repo.ps1 -DryRun

.EXAMPLE
.\Tidy-Repo.ps1 -AutoCommit
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$AutoCommit
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
Set-Location $root

function Ensure-Folder([string]$Path){
  if ($DryRun){ Write-Host "[DRYRUN] mkdir $Path"; return }
  if (-not (Test-Path $Path)){ $null = New-Item -ItemType Directory -Path $Path -Force }
}

function In-GitRepo {
  try {
    $null = git rev-parse --git-dir 2>$null
    return $LASTEXITCODE -eq 0
  } catch { return $false }
}

function Safe-Move([string]$From, [string]$To){
  if (-not (Test-Path $From)){ return }
  Ensure-Folder (Split-Path -Parent $To)
  if (In-GitRepo){
    if ($DryRun){ Write-Host "[DRYRUN] git mv `"$From`" `"$To`""; return }
    git mv "$From" "$To" | Out-Null
  } else {
    if ($DryRun){ Write-Host "[DRYRUN] Move-Item `"$From`" `"$To`""; return }
    Move-Item -Force "$From" "$To"
  }
}

function Safe-RemoveGit([string]$Path){
  if (-not (Test-Path $Path)){ return }
  if (In-GitRepo){
    if ($DryRun){ Write-Host "[DRYRUN] git rm -f `"$Path`""; return }
    git rm -f "$Path" | Out-Null
  } else {
    if ($DryRun){ Write-Host "[DRYRUN] Remove-Item -Force `"$Path`""; return }
    Remove-Item -Force "$Path"
  }
}

Write-Host "=== PowerShell Playbook — Repo Tidy ==="
Write-Host "Root: $root"
Write-Host ""

# Ensure structure
Ensure-Folder "scripts/dev"
Ensure-Folder "scripts/tools"
Ensure-Folder "docs/images"

# Map files to move into /scripts/dev (scaffolding/maintenance helpers)
$devMoves = @(
  "Add-Identity-Governance.ps1",
  "Fix-PesterBootstrap.ps1",
  "Fix-PesterHeaders.ps1",
  "Fix-Tests-And-Manifest.ps1",
  "Make-ExportsWildcard.ps1",
  "Safe-MakeExportsWildcard.ps1",
  "Organize-Repo.ps1",
  "Patch-IdentityFunctions.ps1"
)

# Tools & runners
$toolMoves = @(
  "Start-ReportServer.sh"
)

foreach($f in $devMoves){
  Safe-Move $f ("scripts/dev/" + $f)
}
foreach($f in $toolMoves){
  Safe-Move $f ("scripts/tools/" + $f)
}

# Remove obsolete workspace & cached artifacts from git
$obsolete = @(
  "EnterpriseOpsToolkit.code-workspace"
)
foreach($f in $obsolete){ Safe-RemoveGit $f }

# Clean up test artifacts from git index (keep locally via .gitignore)
$artifacts = @("testResults.xml","test-results.xml")
foreach($a in $artifacts){
  if (Test-Path $a){
    if (In-GitRepo){
      if ($DryRun){ Write-Host "[DRYRUN] git rm -f --cached `"$a`"" }
      else { git rm -f --cached "$a" | Out-Null }
    }
  }
}

# Ensure .gitignore includes our patterns (idempotent)
$ignoreAdd = @(
  "/reports/",
  "/out/",
  "test-results.xml",
  "testResults.xml",
  "*.zip",
  ".DS_Store",
  "Thumbs.db",
  "*.code-workspace"
)

$gitignore = ".gitignore"
if (-not (Test-Path $gitignore)) {
  if ($DryRun){ Write-Host "[DRYRUN] create .gitignore" }
  else { New-Item -ItemType File -Path $gitignore | Out-Null }
}

$current = Get-Content $gitignore -Raw
$updated = $false
foreach($line in $ignoreAdd){
  if ($current -notmatch [regex]::Escape($line)){
    if ($DryRun){ Write-Host "[DRYRUN] append to .gitignore: $line" }
    else { Add-Content -Path $gitignore -Value $line; $updated = $true }
  }
}
if ($updated){ Write-Host ".gitignore updated." }

# Optionally normalize README image path if we detect a common old one
$readme = "README.md"
if (Test-Path $readme){
  $content = Get-Content $readme -Raw
  $replacements = @{
    # If you had an older path, add mappings here:
    # 'assets/sample-report.png' = 'docs/images/sample-report.png'
  }
  $changed = $false
  foreach($k in $replacements.Keys){
    if ($content -match [regex]::Escape($k)){
      $content = $content -replace [regex]::Escape($k), [string]$replacements[$k]
      $changed = $true
    }
  }
  if ($changed){
    if ($DryRun){ Write-Host "[DRYRUN] README path normalizations applied" }
    else { Set-Content -Path $readme -Value $content -Encoding UTF8 }
  }
}

# Auto-commit (optional)
if ($AutoCommit -and (In-GitRepo)) {
  if ($DryRun){
    Write-Host "[DRYRUN] git add -A"
    Write-Host "[DRYRUN] git commit -m `"chore: repo tidy — move helpers to scripts/, ignore artifacts`""
    Write-Host "[DRYRUN] git push"
  } else {
    git add -A
    git commit -m "chore: repo tidy — move helpers to scripts/, ignore artifacts" | Out-Null
    git push
  }
}

Write-Host ""
Write-Host "Done."
if (-not $AutoCommit) {
  Write-Host "Next:"
  Write-Host "  git add -A"
  Write-Host "  git commit -m \"chore: repo tidy — move helpers to scripts/, ignore artifacts\""
  Write-Host "  git push"
}
