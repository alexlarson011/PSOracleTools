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