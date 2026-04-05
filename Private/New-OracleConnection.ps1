function New-OracleConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionString
    )

    if (-not (Test-OracleAssemblyLoaded)) {
        throw 'Oracle.ManagedDataAccess assembly is not loaded. Run Initialize-OracleClient first.'
    }

    $connection = New-Object Oracle.ManagedDataAccess.Client.OracleConnection($ConnectionString)
    return $connection
}