<#
.SYNOPSIS
Returns the active PSOracleTools module configuration.

.DESCRIPTION
Shows the current module-level store paths used for saved Oracle credentials and connection profiles.
These values are initialized when the module is imported and can be changed for the current session.
Also reports whether Microsoft.PowerShell.SecretManagement commands are available for optional secret-backed credentials.

.EXAMPLE
Get-OracleModuleConfiguration

Shows the active credential and profile store paths.
#>
function Get-OracleModuleConfiguration {
    [CmdletBinding()]
    param()

    $secretManagement = Test-OracleSecretManagementAvailable

    New-OracleResult -TypeName 'PSOracleTools.ModuleConfiguration' -Property ([ordered]@{
        CredentialStorePath        = Get-OracleCredentialStorePath
        ProfileStorePath           = Get-OracleProfileStorePath
        EnvironmentCredentialStore = $env:PSORACLETOOLS_CREDENTIAL_STORE
        EnvironmentProfileStore    = $env:PSORACLETOOLS_PROFILE_STORE
        SecretManagementAvailable  = $secretManagement.Available
        SecretManagementMissing    = $secretManagement.MissingCommands
    })
}
