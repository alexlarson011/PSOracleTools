function Initialize-OracleStoreConfiguration {
    [CmdletBinding()]
    param()

    $defaults = Get-OracleDefaultStoreConfiguration

    $script:PSOracleTools.CredentialStorePath = $defaults.CredentialStorePath
    $script:PSOracleTools.ProfileStorePath = $defaults.ProfileStorePath

    return [pscustomobject]@{
        CredentialStorePath = $script:PSOracleTools.CredentialStorePath
        ProfileStorePath    = $script:PSOracleTools.ProfileStorePath
    }
}
