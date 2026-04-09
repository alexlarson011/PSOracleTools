<#
.SYNOPSIS
Updates PSOracleTools module configuration for the current session.

.DESCRIPTION
Sets the module-level store paths used for saved Oracle credentials and connection profiles.
These values apply to subsequent commands in the current imported module session.
Use -ResetToDefault to re-apply the import-time defaults based on environment variables or the AppData store.

.PARAMETER CredentialStorePath
Credential store path to use for the current session.

.PARAMETER ProfileStorePath
Profile store path to use for the current session.

.PARAMETER ResetToDefault
Resets module configuration to the default AppData or environment-variable-based paths.

.EXAMPLE
Set-OracleModuleConfiguration -ProfileStorePath 'C:\config\oracle-profiles.json'

Updates the profile store path for the current session.

.EXAMPLE
Set-OracleModuleConfiguration -ResetToDefault

Resets both store paths to their default values.
#>
function Set-OracleModuleConfiguration {
    [CmdletBinding(DefaultParameterSetName = 'Set')]
    param(
        [Parameter(ParameterSetName = 'Set')]
        [string]$CredentialStorePath,

        [Parameter(ParameterSetName = 'Set')]
        [string]$ProfileStorePath,

        [Parameter(Mandatory, ParameterSetName = 'Reset')]
        [switch]$ResetToDefault
    )

    if ($PSCmdlet.ParameterSetName -eq 'Reset') {
        Initialize-OracleStoreConfiguration | Out-Null
        return Get-OracleModuleConfiguration
    }

    if (-not $PSBoundParameters.ContainsKey('CredentialStorePath') -and -not $PSBoundParameters.ContainsKey('ProfileStorePath')) {
        throw 'Provide at least one store path or use -ResetToDefault.'
    }

    if ($PSBoundParameters.ContainsKey('CredentialStorePath')) {
        $script:PSOracleTools.CredentialStorePath = $CredentialStorePath
    }

    if ($PSBoundParameters.ContainsKey('ProfileStorePath')) {
        $script:PSOracleTools.ProfileStorePath = $ProfileStorePath
    }

    return Get-OracleModuleConfiguration
}
