function New-OracleResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Property,

        [Parameter(Mandatory)]
        [string]$TypeName
    )

    $result = [pscustomobject]$Property
    $result.PSObject.TypeNames.Insert(0, $TypeName)
    return $result
}
