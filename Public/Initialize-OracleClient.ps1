function Initialize-OracleClient {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$DllPath = (Join-Path -Path $PSScriptRoot.Replace('\Public', '') -ChildPath 'lib\Oracle.ManagedDataAccess.dll')
    )

    Import-OracleAssembly -DllPath $DllPath

    [pscustomobject]@{
        Success   = $true
        DllPath   = $DllPath
        Loaded    = (Test-OracleAssemblyLoaded)
        Timestamp = Get-Date
    }
}