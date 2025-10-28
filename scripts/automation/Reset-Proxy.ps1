<#
.SYNOPSIS
  Shows or resets WinHTTP and WinINET proxy settings.
.PARAMETER Show
  Show current proxy configuration.
.PARAMETER Clear
  Clear WinHTTP and WinINET proxy.
.PARAMETER Set
  Set WinINET proxy for current user and WinHTTP proxy (optional).
.PARAMETER Proxy
  Proxy server (e.g. http://proxy.corp:8080) for -Set.
.PARAMETER Bypass
  Semicolon-separated bypass list for -Set (e.g. "localhost;*.corp.local")
.EXAMPLE
  .\Reset-Proxy.ps1 -Show
  .\Reset-Proxy.ps1 -Clear
  .\Reset-Proxy.ps1 -Set -Proxy http://proxy:8080 -Bypass "localhost;*.corp"
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$Show,
  [switch]$Clear,
  [switch]$Set,
  [string]$Proxy,
  [string]$Bypass
)

function Show-WinHttp {
  Write-Host "`n=== WinHTTP ==="
  netsh winhttp show proxy
}

function Show-WinInet {
  Write-Host "`n=== WinINET (Current User) ==="
  $reg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
  Get-ItemProperty -Path $reg | Select-Object ProxyEnable, ProxyServer, ProxyOverride | Format-List
}

if ($Show) { Show-WinHttp; Show-WinInet; return }

if ($Clear) {
  if ($PSCmdlet.ShouldProcess("Proxy","Clear WinHTTP/WinINET")) {
    netsh winhttp reset proxy | Out-Null
    $reg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -Path $reg -Name ProxyEnable -Value 0 -Type DWord
    Remove-ItemProperty -Path $reg -Name ProxyServer -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $reg -Name ProxyOverride -ErrorAction SilentlyContinue
    Write-Host "Proxy cleared."
  }
  return
}

if ($Set) {
  if (-not $Proxy) { throw "Use -Proxy to specify proxy server when using -Set." }
  if ($PSCmdlet.ShouldProcess("Proxy","Set WinINET/WinHTTP")) {
    $reg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -Path $reg -Name ProxyEnable -Value 1 -Type DWord
    Set-ItemProperty -Path $reg -Name ProxyServer -Value $Proxy
    if ($Bypass) { Set-ItemProperty -Path $reg -Name ProxyOverride -Value $Bypass }
    netsh winhttp set proxy proxy-server="$Proxy" @( $Bypass ? "bypass-list=$Bypass" : $null ) | Out-Null
    Write-Host "Proxy set."
  }
  return
}

Write-Host "Nothing to do. Use -Show, -Clear, or -Set."
