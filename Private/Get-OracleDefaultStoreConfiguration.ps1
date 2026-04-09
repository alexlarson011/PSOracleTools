function Get-OracleDefaultStoreConfiguration {
    [CmdletBinding()]
    param()

    $root = Get-OracleToolsRoot

    [pscustomobject]@{
        CredentialStorePath = if ($env:PSORACLETOOLS_CREDENTIAL_STORE) {
            $env:PSORACLETOOLS_CREDENTIAL_STORE
        }
        else {
            Join-Path -Path $root -ChildPath 'credentials.json'
        }
        ProfileStorePath = if ($env:PSORACLETOOLS_PROFILE_STORE) {
            $env:PSORACLETOOLS_PROFILE_STORE
        }
        else {
            Join-Path -Path $root -ChildPath 'profiles.json'
        }
    }
}
