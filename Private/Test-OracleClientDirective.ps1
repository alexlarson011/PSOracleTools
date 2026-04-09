function Test-OracleClientDirective {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StatementText
    )

    $candidate = $StatementText

    while ($true) {
        if ($candidate -match '^\s+') {
            $candidate = $candidate.Substring($matches[0].Length)
            continue
        }

        if ($candidate -match '^(?:--[^\n]*(?:\n|$))') {
            $candidate = $candidate.Substring($matches[0].Length)
            continue
        }

        if ($candidate -match '^(?s)/\*.*?\*/') {
            $candidate = $candidate.Substring($matches[0].Length)
            continue
        }

        break
    }

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $false
    }

    return $candidate -match '^(?i:(?:set|prompt|spool|define|undefine|rem|remark|whenever|pause))\b'
}
