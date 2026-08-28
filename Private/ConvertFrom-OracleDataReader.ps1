function ConvertFrom-OracleDataReader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Reader,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRows
    )

    $rows = New-Object System.Collections.Generic.List[object]

    while ($Reader.Read()) {
        $obj = [ordered]@{}

        for ($i = 0; $i -lt $Reader.FieldCount; $i++) {
            $name = $Reader.GetName($i)
            $value = if ($Reader.IsDBNull($i)) { $null } else { $Reader.GetValue($i) }
            $obj[$name] = $value
        }

        $rows.Add([pscustomobject]$obj)

        if ($PSBoundParameters.ContainsKey('MaxRows') -and $rows.Count -ge $MaxRows) {
            break
        }
    }

    return $rows.ToArray()
}
