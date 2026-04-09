function Test-OraclePlSqlLikeText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $trimmed = $Text.Trim()

    return ($trimmed -match '^(?is)(declare|begin)\b' -or
        $trimmed -match '^(?is)create\s+(or\s+replace\s+)?(procedure|function|package(\s+body)?|trigger|type(\s+body)?)\b')
}
