<#
.SYNOPSIS
Returns the active PSOracleTools module configuration.

.DESCRIPTION
Shows the current module-level store paths used for saved Oracle credentials and connection profiles.
These values are initialized when the module is imported and can be changed for the current session.

.EXAMPLE
Get-OracleModuleConfiguration

Shows the active credential and profile store paths.
#>
function Get-OracleModuleConfiguration {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        CredentialStorePath        = Get-OracleCredentialStorePath
        ProfileStorePath           = Get-OracleProfileStorePath
        EnvironmentCredentialStore = $env:PSORACLETOOLS_CREDENTIAL_STORE
        EnvironmentProfileStore    = $env:PSORACLETOOLS_PROFILE_STORE
    }
}
