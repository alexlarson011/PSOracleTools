function Resolve-OracleIdentifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$Description = 'Oracle identifier'
    )

    $value = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "$Description cannot be empty."
    }

    if ($value.IndexOfAny([char[]]@("`0", "`r", "`n")) -ge 0) {
        throw "$Description contains unsupported control characters."
    }

    $startsQuoted = $value.StartsWith('"')
    $endsQuoted = $value.EndsWith('"')

    if ($startsQuoted -or $endsQuoted) {
        if (-not ($startsQuoted -and $endsQuoted) -or $value.Length -lt 2) {
            throw "$Description has an unmatched double quote."
        }

        $inner = $value.Substring(1, $value.Length - 2)
        if ($inner.Length -eq 0) {
            throw "$Description cannot be empty."
        }

        if ($inner.Replace('""', '').Contains('"')) {
            throw "$Description contains an unescaped double quote. Double embedded quotes inside quoted identifiers."
        }

        $dictionaryName = $inner.Replace('""', '"')
    }
    else {
        if ($value -notmatch '^[\p{L}][\p{L}\p{Nd}_$#]*$') {
            throw "$Description [$Name] is not a valid unquoted Oracle identifier. Pass schema and object names separately, or surround a case-sensitive identifier with double quotes."
        }

        $dictionaryName = $value.ToUpperInvariant()
    }

    return [pscustomobject]@{
        Name = $dictionaryName
        Sql  = '"' + $dictionaryName.Replace('"', '""') + '"'
    }
}
