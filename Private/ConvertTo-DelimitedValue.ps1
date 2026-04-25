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
        [switch]$QuoteAll,

        [Parameter()]
        [string]$DateFormat,

        [Parameter()]
        [string]$DateTimeFormat,

        [Parameter()]
        [System.Globalization.CultureInfo]$Culture = [System.Globalization.CultureInfo]::CurrentCulture
    )

    if ($null -eq $Value) {
        return $NullValue
    }

    if ($Value -is [datetimeoffset]) {
        $Value = $Value.DateTime
    }

    if ($Value -is [datetime]) {
        $format = if ($Value.TimeOfDay.Ticks -eq 0 -and $DateFormat) {
            $DateFormat
        }
        elseif ($DateTimeFormat) {
            $DateTimeFormat
        }
        elseif ($DateFormat) {
            $DateFormat
        }
        else {
            $null
        }

        $text = if ($format) {
            $Value.ToString($format, $Culture)
        }
        else {
            $Value.ToString($Culture)
        }
    }
    elseif ($Value -is [System.IFormattable]) {
        $text = $Value.ToString($null, $Culture)
    }
    else {
        $text = [string]$Value
    }

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
