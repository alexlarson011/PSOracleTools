<#
.SYNOPSIS
Creates an OracleParameter for use with parameterized commands.

.DESCRIPTION
Builds an Oracle.ManagedDataAccess.Client.OracleParameter with the specified name, value, type, direction, and size.
Use the returned parameter object with Invoke-OracleQuery, Invoke-OracleScalar, Invoke-OracleNonQuery, or Invoke-OraclePlSql.

.PARAMETER Name
Parameter name.

.PARAMETER Value
Parameter value. Null is converted to DBNull.Value.

.PARAMETER OracleDbType
Optional Oracle database type.

.PARAMETER Direction
Parameter direction. Defaults to Input.

.PARAMETER Size
Optional parameter size.

.EXAMPLE
New-OracleParameter -Name 'movie_id' -Value 1 -OracleDbType Int32

Creates an input parameter for a numeric movie id.
#>
function New-OracleParameter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        $Value,

        [Parameter()]
        [Oracle.ManagedDataAccess.Client.OracleDbType]$OracleDbType,

        [Parameter()]
        [System.Data.ParameterDirection]$Direction = [System.Data.ParameterDirection]::Input,

        [Parameter()]
        [int]$Size
    )

    $param = New-Object Oracle.ManagedDataAccess.Client.OracleParameter
    $param.ParameterName = $Name
    $param.Direction = $Direction

    if ($PSBoundParameters.ContainsKey('OracleDbType')) {
        $param.OracleDbType = $OracleDbType
    }

    if ($PSBoundParameters.ContainsKey('Size')) {
        $param.Size = $Size
    }

    $param.Value = if ($null -eq $Value) { [DBNull]::Value } else { $Value }

    return $param
}
