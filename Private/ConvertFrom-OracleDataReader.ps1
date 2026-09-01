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
    $usedColumnNames = @{}
    $columnNames = @(
        for ($i = 0; $i -lt $Reader.FieldCount; $i++) {
            $baseName = [string]$Reader.GetName($i)
            if ([string]::IsNullOrWhiteSpace($baseName)) {
                $baseName = 'Column{0}' -f ($i + 1)
            }

            $name = $baseName
            $suffix = 2
            while ($usedColumnNames.ContainsKey($name)) {
                $name = '{0}_{1}' -f $baseName, $suffix
                $suffix++
            }

            $usedColumnNames[$name] = $true
            $name
        }
    )

    while ($Reader.Read()) {
        $obj = [ordered]@{}

        for ($i = 0; $i -lt $Reader.FieldCount; $i++) {
            $value = if ($Reader.IsDBNull($i)) { $null } else { $Reader.GetValue($i) }
            $obj[$columnNames[$i]] = $value
        }

        $rows.Add([pscustomobject]$obj)

        if ($PSBoundParameters.ContainsKey('MaxRows') -and $rows.Count -ge $MaxRows) {
            break
        }
    }

    return $rows.ToArray()
}
