function Get-OracleParameterSummary {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Parameters
    )

    if ($null -eq $Parameters) {
        return @()
    }

    if ($Parameters -is [hashtable]) {
        $summary = foreach ($key in ($Parameters.Keys | Sort-Object)) {
            $value = $Parameters[$key]
            $typeName = if ($null -eq $value) { 'null' } else { $value.GetType().Name }
            '{0}={1}' -f $key, $typeName
        }

        return @($summary)
    }

    $summary = foreach ($param in $Parameters) {
        $name = if ($param.PSObject.Properties['ParameterName']) { $param.ParameterName } else { '<unknown>' }
        $typeName = if ($param.PSObject.Properties['OracleDbType']) { $param.OracleDbType } else { $param.GetType().Name }
        $direction = if ($param.PSObject.Properties['Direction']) { $param.Direction } else { 'Input' }
        '{0}({1},{2})' -f $name, $typeName, $direction
    }

    return @($summary)
}
