function New-OracleConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionString
    )

    if (-not (Test-OracleAssemblyLoaded)) {
        throw 'Oracle.ManagedDataAccess assembly is not loaded. Run Initialize-OracleClient first.'
    }

    try {
        $connection = New-Object Oracle.ManagedDataAccess.Client.OracleConnection($ConnectionString)
        return $connection
    }
    catch {
        throw "Failed to create Oracle connection. $(Get-OracleExceptionMessage -Exception $_.Exception)"
    }
}
