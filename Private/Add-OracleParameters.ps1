function Add-OracleParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Command,

        [Parameter()]
        $Parameters
    )

    if ($null -eq $Parameters) {
        return
    }

    if ($Parameters -is [hashtable]) {
        foreach ($key in $Parameters.Keys) {
            $param = New-Object Oracle.ManagedDataAccess.Client.OracleParameter
            $param.ParameterName = [string]$key
            $param.Value = if ($null -eq $Parameters[$key]) { [DBNull]::Value } else { $Parameters[$key] }
            [void]$Command.Parameters.Add($param)
        }
        return
    }

    foreach ($param in $Parameters) {
        [void]$Command.Parameters.Add($param)
    }
}