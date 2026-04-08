function Open-OracleConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Oracle.ManagedDataAccess.Client.OracleConnection]$Connection
    )

    try {
        if ($Connection.State -ne [System.Data.ConnectionState]::Open) {
            $Connection.Open()
        }

        return $Connection
    }
    catch {
        throw "Failed to open Oracle connection. $(Get-OracleExceptionMessage -Exception $_.Exception)"
    }
}
