function ConvertTo-DelimitedValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value,

        [Parameter()]
        [string]$Delimiter = '|',

        [Parameter()]
        [string]$NullValue = '',

        [Parameter()]
        [switch]$QuoteAll
    )

    if ($null -eq $Value) {
        return $NullValue
    }

    $text = [string]$Value
    $mustQuote = $QuoteAll -or
                 $text.Contains($Delimiter) -or
                 $text.Contains('"') -or
                 $text.Contains("`r") -or
                 $text.Contains("`n")

    if ($text.Contains('"')) {
        $text = $text.Replace('"', '""')
    }

    if ($mustQuote) {
        return '"' + $text + '"'
    }

    return $text
}