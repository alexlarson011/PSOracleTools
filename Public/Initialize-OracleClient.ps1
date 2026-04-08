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
