function Normalize-OracleCommandText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter()]
        [ValidateSet('Sql', 'PlSql', 'SqlOrPlSql')]
        [string]$Mode = 'Sql'
    )

    $normalized = $Text.Trim()

    if ($normalized -match '(?s)^(?<body>.*?)(?:\r?\n)\s*/\s*$') {
        $normalized = $matches['body'].TrimEnd()
    }

    if ($Mode -eq 'PlSql') {
        return $normalized
    }

    if ($Mode -eq 'SqlOrPlSql' -and (Test-OraclePlSqlLikeText -Text $normalized)) {
        return $normalized
    }

    if ($normalized.EndsWith(';')) {
        return $normalized.Substring(0, $normalized.Length - 1).TrimEnd()
    }

    return $normalized
}
