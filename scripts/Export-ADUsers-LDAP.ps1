<#
.SYNOPSIS
Export AD users via LDAP (System.DirectoryServices).

.DESCRIPTION
This script queries Active Directory using System.DirectoryServices.DirectorySearcher and
exports basic user properties to CSV. It's a focused helper for LDAP-based environments.

.PARAMETER Server
LDAP server FQDN (required when running off-domain).

.PARAMETER SearchBase
LDAP search base (e.g. DC=contoso,DC=com).

.PARAMETER Filter
LDAP filter to apply. Defaults to a basic user filter.

.PARAMETER OutputPath
Path where CSV output will be written. Directory will be created if necessary.

.EXAMPLE
    .\scripts\Export-ADUsers-LDAP.ps1 -Server dc01.corp.local -SearchBase 'DC=corp,DC=local' -OutputPath .\exports\users.csv
<#
.SYNOPSIS
Export AD users via LDAP (System.DirectoryServices).

.DESCRIPTION
This script queries Active Directory using System.DirectoryServices.DirectorySearcher and
exports basic user properties to CSV. It's a focused helper for LDAP-based environments.

.PARAMETER Server
LDAP server FQDN (required when running off-domain).

.PARAMETER SearchBase
LDAP search base (e.g. DC=contoso,DC=com).

.PARAMETER Filter
LDAP filter to apply. Defaults to a basic user filter.

.PARAMETER OutputPath
Path where CSV output will be written. Directory will be created if necessary.

.EXAMPLE
	.\scripts\Export-ADUsers-LDAP.ps1 -Server dc01.corp.local -SearchBase 'DC=corp,DC=local' -OutputPath .\exports\users.csv
#>

[CmdletBinding()]
param(
	[string]$Server,
	[string]$SearchBase,
	[string]$Filter = '(objectCategory=person)(objectClass=user)',
	[ValidateSet('Base','OneLevel','Subtree')][string]$SearchScope = 'Subtree',
	[int]$PageSize = 1000,
	[int]$ResultSetSize = 0,
	[switch]$UseLDAPS,
	[System.Management.Automation.PSCredential]$Credential,
	[string]$OutputPath = (Join-Path (Get-Location) ("ad_users_export_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))),
	[switch]$NoBOM
)

function Convert-FileTimeToDate { param([string]$Value)
	if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
	try { $ll=[int64]$Value; if ($ll -le 0){return $null}; [DateTime]::FromFileTimeUtc($ll) } catch { $null }
}

function Get-SearchScopeEnum {
	param([string]$Scope)
	switch ($Scope) {
		'Base'     { [System.DirectoryServices.SearchScope]::Base }
		'OneLevel' { [System.DirectoryServices.SearchScope]::OneLevel }
		default    { [System.DirectoryServices.SearchScope]::Subtree }
	}
}

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

function Run-ExportADUsersLDAP {
	try {
		Add-Type -AssemblyName System.DirectoryServices | Out-Null

		# Validate inputs and create DirectoryEntry binding
		$tuple = New-DirectoryEntry -Server $Server -SearchBase $SearchBase -UseLDAPS:$UseLDAPS -Credential $Credential
		$ldapPath,$entry = $tuple[0],$tuple[1]
		Write-Verbose "LDAP Path : $ldapPath"
		Write-Verbose "LDAP Scope: $SearchScope"
		Write-Verbose "LDAP Filter: $Filter"
		$searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
		$searcher.Filter = $Filter
		$searcher.SearchScope = Get-SearchScopeEnum -Scope $SearchScope
		$searcher.PageSize = [Math]::Max($PageSize, 1)
		if ($ResultSetSize -gt 0) { $searcher.SizeLimit = $ResultSetSize }

		foreach ($p in @( 
			'name','cn','sn','givenName','displayName',
			'sAMAccountName','userPrincipalName','mail','department','title','manager',
			'userAccountControl','lastLogonTimestamp','pwdLastSet','whenCreated','distinguishedName'
		)) { [void]$searcher.PropertiesToLoad.Add($p) }

		$results = $searcher.FindAll()
	} catch {
		throw "LDAP search failed. Inner: $($_.Exception.Message)"
	}

	if (-not $results -or $results.Count -eq 0) { Write-Warning "No users found."; return }

	$rows = foreach ($res in $results) {
		$it = $res.Properties
		function _g($n){ if ($it.Contains($n)) { $it[$n][0] } else { $null } }

		$uac = _g 'useraccountcontrol'; if ($uac) { $uac = [int]$uac }
		[pscustomobject]@{
			Name = (_g 'name') ?? (_g 'cn')
			GivenName = _g 'givenname'
			Surname = _g 'sn'
			DisplayName = _g 'displayname'
			SamAccountName = _g 'samaccountname'
			UserPrincipalName = _g 'userprincipalname'
			EmailAddress = _g 'mail'
			Department = _g 'department'
			Title = _g 'title'
			Manager = _g 'manager'
			Enabled = if ($uac -ne $null) { -not (($uac -band 2) -ne 0) } else { $null }
			LastLogonDate = Convert-FileTimeToDate (_g 'lastlogontimestamp')
			PasswordLastSet = Convert-FileTimeToDate (_g 'pwdlastset')
			WhenCreated = if (_g 'whencreated') { [datetime](_g 'whencreated') } else { $null }
			DistinguishedName = _g 'distinguishedname'
		}
	}

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

	Write-Host ("Export complete → {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor Green
}

# Only execute when the script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') { Run-ExportADUsersLDAP }