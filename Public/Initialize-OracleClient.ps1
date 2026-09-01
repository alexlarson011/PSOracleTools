<#
.SYNOPSIS
Initializes the Oracle managed client for the current PowerShell session.

.DESCRIPTION
Loads Oracle.ManagedDataAccess and the module's side-by-side dependency DLLs from the lib folder.
Also applies Oracle client configuration from TNS_ADMIN so wallet and tnsnames.ora based connections work.
If a different Oracle managed driver is already loaded, reports the conflict and requires a fresh PowerShell process.

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
        [string]$DllPath = (Get-OracleBundledDllPath -ModuleRoot $PSScriptRoot.Replace('\Public', ''))
    )

    $startedOn = Get-Date
    $effectiveDllPath = Import-OracleAssembly -DllPath $DllPath
    $configuration = Set-OracleClientConfiguration

    New-OracleResult -TypeName 'PSOracleTools.ClientInitializationResult' -Property ([ordered]@{
        Success                     = $true
        Operation                   = 'Initialize-OracleClient'
        DllPath                     = $effectiveDllPath
        Loaded                      = (Test-OracleAssemblyLoaded)
        TnsAdmin                    = $configuration.TnsAdmin
        WalletLocation              = $configuration.WalletLocation
        OpenTelemetryTracing        = $configuration.OpenTelemetryTracing
        DatabaseOpenTelemetryTracing = $configuration.DatabaseOpenTelemetryTracing
        StartedOn                   = $startedOn
        CompletedOn                 = Get-Date
    })
}
