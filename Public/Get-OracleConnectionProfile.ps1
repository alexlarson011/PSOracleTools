<#
.SYNOPSIS
Reads Oracle connection profile metadata.

.DESCRIPTION
Returns one named connection profile or all profiles from the configured profile store.

.PARAMETER Name
Optional profile name to retrieve.

.PARAMETER ProfileStorePath
Optional custom path to the profile store JSON file.

.EXAMPLE
Get-OracleConnectionProfile

Lists all stored connection profiles.
#>
function Get-OracleConnectionProfile {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$ProfileStorePath
    )

    $path = Get-OracleProfileStorePath -ProfileStorePath $ProfileStorePath

    if (-not (Test-Path -Path $path)) {
        throw "No profile store found at [$path]."
    }

    $profiles = Read-OracleNamedRecordStore -Path $path -StoreDescription 'connection profile'

    if ($Name) {
        $profile = $profiles | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

        if (-not $profile) {
            throw "Connection profile [$Name] not found."
        }

        return $profile
    }

    return $profiles
}
