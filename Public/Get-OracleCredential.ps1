<#
.SYNOPSIS
Reads saved Oracle credential metadata from the credential store.

.DESCRIPTION
Returns one saved credential record or all saved credential records from the configured credential store.
The returned object includes the stored user name and encrypted password metadata.

.PARAMETER Name
Optional credential name to retrieve.

.PARAMETER CredentialStorePath
Optional custom path to the credential store JSON file.

.EXAMPLE
Get-OracleCredential

Lists all saved credential records.

.EXAMPLE
Get-OracleCredential -Name 'ProdLow' -CredentialStorePath '.\config\oracle-creds.json'

Returns one saved credential record from a custom store path.
#>
function Get-OracleCredential {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$CredentialStorePath
    )

    $path = Get-OracleCredentialStorePath -CredentialStorePath $CredentialStorePath

    if (-not (Test-Path -Path $path)) {
        throw 'No credential store found.'
    }

    $records = Read-OracleNamedRecordStore -Path $path -StoreDescription 'credential'

    if ($Name) {
        $record = $records | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

        if (-not $record) {
            throw "Credential [$Name] not found."
        }

        return $record
    }

    return $records
}
