function Get-OracleCredential {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name
    )

    $path = Get-OracleCredentialStorePath

    if (-not (Test-Path -Path $path)) {
        throw 'No credential store found.'
    }

    $records = Get-Content -Path $path -Raw | ConvertFrom-Json

    if ($Name) {
        $record = $records | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

        if (-not $record) {
            throw "Credential [$Name] not found."
        }

        return $record
    }

    return $records
}