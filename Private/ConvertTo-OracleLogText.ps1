function ConvertTo-OracleLogText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $normalized = $normalized.Trim()
    $normalized = ($normalized -split "`n" | ForEach-Object { $_.Trim() }) -join '\n'

    return $normalized
}
