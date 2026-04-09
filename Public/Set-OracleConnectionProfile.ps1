<#
.SYNOPSIS
Stores a named Oracle connection profile.

.DESCRIPTION
Stores non-secret Oracle connection settings such as data source, credential name, timeout, and logging defaults.
Profiles are intended to reduce repeated connection arguments across commands.

.PARAMETER Name
Profile name.

.PARAMETER DataSource
Oracle data source or TNS alias.

.PARAMETER CredentialName
Saved credential name associated with the profile.

.PARAMETER CredentialStorePath
Optional credential store path associated with the profile.

.PARAMETER CommandTimeout
Default command timeout in seconds.

.PARAMETER ConnectionTimeout
Default connection timeout in seconds.

.PARAMETER LogPath
Default log file path.

.PARAMETER LogSql
Enables SQL logging by default for profile-based runs.

.PARAMETER LogParameters
Enables parameter logging by default for profile-based runs.

.PARAMETER ProfileStorePath
Optional custom path to the profile store JSON file.

.EXAMPLE
Set-OracleConnectionProfile -Name 'ProdLow' -DataSource 'mydb_low' -CredentialName 'ProdCred'

Creates a simple reusable connection profile.
#>
function Set-OracleConnectionProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$DataSource,

        [Parameter()]
        [string]$CredentialName,

        [Parameter()]
        [string]$CredentialStorePath,

        [Parameter()]
        [int]$CommandTimeout,

        [Parameter()]
        [int]$ConnectionTimeout,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [bool]$LogSql = $false,

        [Parameter()]
        [bool]$LogParameters = $false,

        [Parameter()]
        [string]$ProfileStorePath
    )

    $path = Get-OracleProfileStorePath -ProfileStorePath $ProfileStorePath
    $profiles = @()

    if (Test-Path -Path $path) {
        $profiles = Read-OracleNamedRecordStore -Path $path -StoreDescription 'connection profile'
    }

    $profiles = @($profiles | Where-Object { $_.Name -ne $Name })

    $profile = [pscustomobject]@{
        Name                = $Name
        DataSource          = $DataSource
        CredentialName      = $CredentialName
        CredentialStorePath = $CredentialStorePath
        CommandTimeout      = $CommandTimeout
        ConnectionTimeout   = $ConnectionTimeout
        LogPath             = $LogPath
        LogSql              = $LogSql
        LogParameters       = $LogParameters
        UpdatedOn           = Get-Date
    }

    $profiles += $profile

    $directory = Split-Path -Path $path -Parent
    if ($directory -and -not (Test-Path -Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $profiles | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8

    [pscustomobject]@{
        Name      = $Name
        DataSource = $DataSource
        UpdatedOn = $profile.UpdatedOn
        Path      = $path
    }
}
