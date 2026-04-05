function New-OracleCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Oracle.ManagedDataAccess.Client.OracleConnection]$Connection,

        [Parameter(Mandatory)]
        [string]$CommandText,

        [Parameter()]
        [int]$CommandTimeout = 300,

        [Parameter()]
        [System.Data.CommandType]$CommandType = [System.Data.CommandType]::Text
    )

    $command = $Connection.CreateCommand()
    $command.BindByName = $true
    $command.CommandText = $CommandText
    $command.CommandTimeout = $CommandTimeout
    $command.CommandType = $CommandType

    return $command
}