function Get-OracleCredentialStorePath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$CredentialStorePath
    )

    if ($CredentialStorePath) {
        return $CredentialStorePath
    }

    if ($script:PSOracleTools.CredentialStorePath) {
        return $script:PSOracleTools.CredentialStorePath
    }

    return (Get-OracleDefaultStoreConfiguration).CredentialStorePath
}
