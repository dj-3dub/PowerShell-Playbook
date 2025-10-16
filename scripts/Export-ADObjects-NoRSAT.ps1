[<#
.SYNOPSIS
NO-RSAT AD Exporter with optional MOCK mode for offline testing.

.DESCRIPTION
This script can export AD objects via System.DirectoryServices (REAL mode) or simulate exports
when RSAT/System.DirectoryServices is not available using `-Mock` (MOCK mode).

.PARAMETER ObjectType
Type of AD object to export. Valid values: User, Computer, Group, Contact, Custom. Default: User.

.PARAMETER Mock
If present, the script will generate simulated objects locally and write them to `-OutputPath`.

.PARAMETER MockCount
Number of mock objects to generate in `-Mock` mode. Default: 25.

.PARAMETER OutputPath
Path to the CSV output file. Directory will be created if necessary.

.EXAMPLE
  # Generate 50 mock users to exports/users_mock.csv
  .\scripts\Export-ADObjects-NoRSAT.ps1 -ObjectType User -Mock -MockCount 50 -OutputPath .\exports\users_mock.csv -Verbose

.NOTES
When running in REAL mode you must provide -Server and -SearchBase when running off-domain.
#>
[CmdletBinding()]
param(
  [ValidateSet('User','Computer','Group','Contact','Custom')]
  [string]$ObjectType = 'User',
  [string]$Filter = '*',
  [string]$LdapFilter,
  [string]$SearchBase,              # e.g. DC=yourdomain,DC=com
  [ValidateSet('Base','OneLevel','Subtree')] [string]$SearchScope = 'Subtree',
  [string]$Server,                  # e.g. dc01.yourdomain.com (required off-domain for REAL queries)
  [int]$Port,                       # defaults to 389 or 636 depending on -UseLDAPS (REAL mode)
  [switch]$UseLDAPS,                # REAL mode: LDAPS (SSL)
  [System.Management.Automation.PSCredential]$Credential,
  [string[]]$Properties,
  [string]$OutputPath = (Join-Path (Get-Location) ("ad_export_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))),
  [int]$PageSize = 1000,
  [int]$ResultSetSize,
  [switch]$NoDefaultProperties,
  [switch]$NoBOM,
  [switch]$Mock,                    # <<< NEW: simulate data, no LDAP
  [int]$MockCount = 25              # how many rows to simulate
)

# ---------- helpers (shared) ----------
function Convert-FileTimeToDate { param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  try { $ll=[int64]$Value; if ($ll -le 0){return $null}; [DateTime]::FromFileTimeUtc($ll) } catch { $null }
}
function Test-UacFlag { param([int]$Uac,[int]$Flag) ; (($Uac -band $Flag) -ne 0) }
function Get-DefaultProps {
  param([string]$Type)
  switch ($Type) {
    'User'     { @('name','sAMAccountName','userPrincipalName','userAccountControl','whenCreated','lastLogonTimestamp','pwdLastSet','accountExpires','department','title','manager','mail','distinguishedName') }
    'Computer' { @('name','sAMAccountName','dNSHostName','operatingSystem','operatingSystemVersion','userAccountControl','whenCreated','lastLogonTimestamp','distinguishedName') }
    'Group'    { @('name','sAMAccountName','groupType','managedBy','member','whenCreated','distinguishedName') }
    'Contact'  { @('name','displayName','mail','telephoneNumber','company','department','title','whenCreated','distinguishedName') }
    default    { @('name','objectClass','objectGUID','distinguishedName','whenCreated') }
  }
}
function Build-LdapFilter {
  param([string]$Type,[string]$Filter,[string]$LdapFilter)
  if ($LdapFilter) { return $LdapFilter }
  $typeClause = switch ($Type) {
    'User'     { '(objectCategory=person)(objectClass=user)' }
    'Computer' { '(objectCategory=computer)' }
    'Group'    { '(objectCategory=group)' }
    'Contact'  { '(objectClass=contact)' }
    default    { '' }
  }
  $enabledClause = ''
  if ($Filter -match 'Enabled\s*-eq\s*\$true')  { $enabledClause = '(!(userAccountControl:1.2.840.113556.1.4.803:=2))' }
  if ($Filter -match 'Enabled\s*-eq\s*\$false') { $enabledClause = '(userAccountControl:1.2.840.113556.1.4.803:=2)' }
  if ($Type -eq 'Custom' -or [string]::IsNullOrWhiteSpace($typeClause)) { return '(*)' }
  if ($enabledClause) { "(&($typeClause)$enabledClause)" } else { "(&($typeClause))" }
}
function Get-SearchScopeEnum {
  param([string]$Scope)
  switch ($Scope) {
    'Base'     { [System.DirectoryServices.SearchScope]::Base }
    'OneLevel' { [System.DirectoryServices.SearchScope]::OneLevel }
    default    { [System.DirectoryServices.SearchScope]::Subtree }
  }
}

# ---------- MOCK MODE ----------
if ($Mock) {
  Write-Verbose "MOCK mode enabled → generating $MockCount $ObjectType rows (no LDAP)."
  $rand = [System.Random]::new()
  $now  = Get-Date
  $rows = switch ($ObjectType) {
    'User' {
      1..$MockCount | ForEach-Object {
        $i = $_
        $enabled = ($rand.NextDouble() -ge 0.2) # ~80% enabled
        [pscustomobject]@{
          Name               = "User $i"
          SamAccountName     = "user$i"
          UserPrincipalName  = "user$i@corp.example.com"
          Enabled            = $enabled
          WhenCreated        = $now.AddDays(-$rand.Next(30, 2000))
          LastLogonDate      = $now.AddDays(-$rand.Next(0, 90))
          PasswordLastSet    = $now.AddDays(-$rand.Next(0, 365))
          AccountExpires     = $null
          Department         = @('IT','Finance','HR','Ops','Legal')[$rand.Next(0,5)]
          Title              = @('Engineer','Analyst','Admin','Lead','Manager')[$rand.Next(0,5)]
          Manager            = "CN=Manager $([char](65+$rand.Next(0,26))) ,OU=Users,DC=corp,DC=example,DC=com"
          EmailAddress       = "user$i@corp.example.com"
          DistinguishedName  = "CN=User $i,OU=Users,DC=corp,DC=example,DC=com"
        }
      }
    }
    'Computer' {
      1..$MockCount | ForEach-Object {
        $i = $_
        $enabled = ($rand.NextDouble() -ge 0.1)
        [pscustomobject]@{
          Name               = "PC-$("{0:D4}" -f $i)"
          SamAccountName     = "PC-$("{0:D4}" -f $i)$"
          DNSHostName        = "pc-$("{0:D4}" -f $i).corp.example.com"
          OperatingSystem    = @('Windows 11 Pro','Windows 10 Pro','Windows Server 2022','Windows Server 2019')[$rand.Next(0,4)]
          OSVersion          = @('10.0.22631','10.0.19045','10.0.20348','10.0.17763')[$rand.Next(0,4)]
          Enabled            = $enabled
          WhenCreated        = $now.AddDays(-$rand.Next(30, 2000))
          LastLogonDate      = $now.AddDays(-$rand.Next(0, 60))
          DistinguishedName  = "CN=PC-$("{0:D4}" -f $i),OU=Workstations,DC=corp,DC=example,DC=com"
        }
      }
    }
    'Group' {
      1..$MockCount | ForEach-Object {
        $i = $_
        [pscustomobject]@{
          Name               = "Group $i"
          SamAccountName     = "group$i"
          GroupType          = @('Security','Distribution')[$rand.Next(0,2)]
          ManagedBy          = "CN=Manager $([char](65+$rand.Next(0,26))) ,OU=Users,DC=corp,DC=example,DC=com"
          MemberCount        = $rand.Next(1, 250)
          WhenCreated        = $now.AddDays(-$rand.Next(30, 3000))
          DistinguishedName  = "CN=Group $i,OU=Groups,DC=corp,DC=example,DC=com"
        }
      }
    }
    'Contact' {
      1..$MockCount | ForEach-Object {
        $i = $_
        [pscustomobject]@{
          Name               = "Contact $i"
          DisplayName        = "Contact $i"
          EmailAddress       = "contact$i@partners.example.com"
          TelephoneNumber    = "312-555-$("{0:D4}" -f $rand.Next(0,9999))"
          Company            = @('Acme Co','Globex','Initech','Umbrella','Stark')[$rand.Next(0,5)]
          Department         = @('Sales','Support','Ops','Marketing','R&D')[$rand.Next(0,5)]
          Title              = @('Rep','Coordinator','Advisor','Director','VP')[$rand.Next(0,5)]
          WhenCreated        = $now.AddDays(-$rand.Next(30, 2000))
          DistinguishedName  = "CN=Contact $i,OU=Contacts,DC=corp,DC=example,DC=com"
        }
      }
    }
    default {
      1..$MockCount | ForEach-Object {
        $i = $_
        [pscustomobject]@{
          Name               = "Obj $i"
          ObjectClass        = 'user'
          WhenCreated        = $now.AddDays(-$rand.Next(30, 2000))
          DistinguishedName  = "CN=Obj $i,DC=corp,DC=example,DC=com"
        }
      }
    }
  }

  # Ensure output dir exists and export
  $dir = Split-Path -Parent $OutputPath
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if ($NoBOM) {
    $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding utf8
  } else {
    $tmp = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName() + '.csv')
    $rows | Export-Csv -Path $tmp -NoTypeInformation -Encoding utf8
    $utf8bom = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($OutputPath, [IO.File]::ReadAllText($tmp), $utf8bom)
    Remove-Item $tmp -Force
  }
  Write-Host ("MOCK export complete → {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor Green
  return
}

# ---------- REAL LDAP MODE (unchanged from earlier approach) ----------
function New-DirectoryEntry {
  param(
    [string]$Server,[int]$Port,[string]$SearchBase,[switch]$UseLDAPS,
    [System.Management.Automation.PSCredential]$Credential
  )
  if ([string]::IsNullOrWhiteSpace($Server)) { throw "You must supply -Server when not domain-joined." }
  if ([string]::IsNullOrWhiteSpace($SearchBase)) { throw "You must supply -SearchBase (e.g. DC=yourdomain,DC=com)." }
  $effectivePort = if ($Port) { $Port } else { if ($UseLDAPS){636}else{389} }
 $path = "LDAP://${Server}:${effectivePort}/${SearchBase}"
  $auth = if ($UseLDAPS) { [System.DirectoryServices.AuthenticationTypes]::SecureSocketsLayer } else { [System.DirectoryServices.AuthenticationTypes]::Secure }
  if ($Credential) {
    $u = $Credential.UserName; $p = $Credential.GetNetworkCredential().Password
    return ,@($path,(New-Object System.DirectoryServices.DirectoryEntry($path,$u,$p,$auth)))
  } else {
    return ,@($path,(New-Object System.DirectoryServices.DirectoryEntry($path,$null,$null,$auth)))
  }
}

try { Add-Type -AssemblyName System.DirectoryServices | Out-Null } catch { Write-Error "System.DirectoryServices not available."; exit 1 }

# Property set
$propSet = @()
if (-not $NoDefaultProperties) { $propSet += (Get-DefaultProps -Type $ObjectType) }
if ($Properties)              { $propSet += $Properties }
$propSet = $propSet | Select-Object -Unique
$ldap = Build-LdapFilter -Type $ObjectType -Filter $Filter -LdapFilter $LdapFilter

# Bind & search
$tuple = New-DirectoryEntry -Server $Server -Port $Port -SearchBase $SearchBase -UseLDAPS:$UseLDAPS -Credential $Credential
$ldapPath,$entry = $tuple[0],$tuple[1]
Write-Verbose "LDAP Path : $ldapPath"
Write-Verbose "LDAP Scope: $SearchScope"
Write-Verbose "LDAP Filter: $ldap"
if ($UseLDAPS) { Write-Verbose "Protocol  : LDAPS (SSL)" }
if ($Credential) { Write-Verbose "Credential: $(($Credential.UserName))" }

try {
  $searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
  $searcher.Filter      = $ldap
  $searcher.SearchScope = Get-SearchScopeEnum -Scope $SearchScope
  $searcher.PageSize    = [Math]::Max($PageSize, 1)
  if ($ResultSetSize -gt 0) { $searcher.SizeLimit = $ResultSetSize }
  foreach ($p in $propSet) { if ($p) { [void]$searcher.PropertiesToLoad.Add($p) } }
  $results = $searcher.FindAll()
} catch {
  throw "LDAP search failed. Path='$ldapPath' Filter='$ldap'. Inner: $($_.Exception.Message)"
}

if (-not $results -or $results.Count -eq 0) { Write-Warning "No results returned from Active Directory."; return }

# Map → objects (same as before, omitted here for brevity)
# ... (you can keep the full mapping from the earlier version)
