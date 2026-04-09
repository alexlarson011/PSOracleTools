function ConvertFrom-OracleProviderValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $null
    }

    $type = $Value.GetType()
    $fullName = $type.FullName

    if ($fullName -like 'Oracle.ManagedDataAccess.Types.*' -or $fullName -like 'Oracle.ManagedDataAccess.Client.Oracle*') {
        $isNullProperty = $type.GetProperty('IsNull')
        if ($isNullProperty) {
            try {
                if ([bool]$isNullProperty.GetValue($Value, $null)) {
                    return $null
                }
            }
            catch {
            }
        }

        $valueProperty = $type.GetProperty('Value')
        if ($valueProperty) {
            try {
                return $valueProperty.GetValue($Value, $null)
            }
            catch {
            }
        }
    }

    return $Value
}
