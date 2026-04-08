<#
.SYNOPSIS
Initializes the Oracle managed client for the current PowerShell session.

.DESCRIPTION
Loads Oracle.ManagedDataAccess and the module's side-by-side dependency DLLs from the lib folder.
Also applies Oracle client configuration from TNS_ADMIN so wallet and tnsnames.ora based connections work.

.PARAMETER DllPath
Optional path to Oracle.ManagedDataAccess.dll. Defaults to the copy shipped with the module.

.EXAMPLE
Initialize-OracleClient

Loads the bundled Oracle managed client and returns the effective DLL, TNS admin, and wallet paths.
#>
function Initialize-OracleClient {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$DllPath = (Join-Path -Path $PSScriptRoot.Replace('\Public', '') -ChildPath 'lib\Oracle.ManagedDataAccess.dll')
    )

    Import-OracleAssembly -DllPath $DllPath
    $configuration = Set-OracleClientConfiguration

    [pscustomobject]@{
        Success        = $true
        DllPath        = $DllPath
        Loaded         = (Test-OracleAssemblyLoaded)
        TnsAdmin       = $configuration.TnsAdmin
        WalletLocation = $configuration.WalletLocation
        Timestamp      = Get-Date
    }
}
