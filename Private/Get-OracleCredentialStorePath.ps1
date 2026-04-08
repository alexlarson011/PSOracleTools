function Get-OracleCredentialStorePath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$CredentialStorePath
    )

    if ($CredentialStorePath) {
        return $CredentialStorePath
    }

    if ($env:PSORACLETOOLS_CREDENTIAL_STORE) {
        return $env:PSORACLETOOLS_CREDENTIAL_STORE
    }

    $root = Get-OracleToolsRoot
    return (Join-Path -Path $root -ChildPath 'credentials.json')
}
