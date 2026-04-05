function Open-OracleConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Oracle.ManagedDataAccess.Client.OracleConnection]$Connection
    )

    if ($Connection.State -ne [System.Data.ConnectionState]::Open) {
        $Connection.Open()
    }

    return $Connection
}