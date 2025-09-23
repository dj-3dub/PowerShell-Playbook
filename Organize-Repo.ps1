# Organize-Repo.ps1
[CmdletBinding()]
param(
  [string]$RepoRoot = "."
)

$ErrorActionPreference = 'Stop'
Push-Location $RepoRoot

# Ensure target folders exist
$null = New-Item -ItemType Directory -Force -Path "scripts/dev","scripts/ops","src/Public","tests" 

# 1) Move dev/helper scripts from root -> scripts/dev
$helpers = @(
  "Add-NewEotScripts.ps1",
  "Finalize-Renames.ps1",
  "Fix-EotPublicScripts.ps1",
  "Fix-TestsPaths.ps1"
) | Where-Object { Test-Path $_ }

foreach ($h in $helpers) {
  Move-Item -Force -Path $h -Destination "scripts/dev/$h"
  Write-Host "Moved $h -> scripts/dev/$h"
}

# 2) Fix accidental subtrees created under scripts/
if (Test-Path "scripts/src/Public") {
  Get-ChildItem "scripts/src/Public" -File | ForEach-Object {
    Move-Item -Force -Path $_.FullName -Destination "src/Public/"
    Write-Host "Moved public script: $($_.Name) -> src/Public/"
  }
  Remove-Item -Recurse -Force "scripts/src"
  Write-Host "Removed scripts/src"
}

if (Test-Path "scripts/tests") {
  Get-ChildItem "scripts/tests" -File | ForEach-Object {
    Move-Item -Force -Path $_.FullName -Destination "tests/"
    Write-Host "Moved test file: $($_.Name) -> tests/"
  }
  Remove-Item -Recurse -Force "scripts/tests"
  Write-Host "Removed scripts/tests"
}

# 3) Remove stray literal $OutputPath directory under scripts
if (Test-Path "scripts/`$OutputPath") {
  Remove-Item -Recurse -Force "scripts/`$OutputPath"
  Write-Host "Removed scripts/\$OutputPath"
}

Pop-Location
Write-Host "`nRepo organization complete." -ForegroundColor Cyan
