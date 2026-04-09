function ConvertTo-ExcelCellXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 16384)]
        [int]$ColumnIndex,

        [Parameter(Mandatory)]
        [ValidateRange(1, 1048576)]
        [int]$RowIndex,

        [AllowNull()]
        $Value,

        [Parameter()]
        [string]$NullValue = '',

        [Parameter()]
        [switch]$Header,

        [Parameter()]
        [bool]$BoldHeader = $false
    )

    $cellReference = '{0}{1}' -f (ConvertTo-ExcelColumnName -Index $ColumnIndex), $RowIndex
    $culture = [System.Globalization.CultureInfo]::InvariantCulture

    $escapeText = {
        param([string]$Text)

        if ($null -eq $Text) {
            return ''
        }

        $sanitized = $Text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
        return [System.Security.SecurityElement]::Escape($sanitized)
    }

    if ($Header) {
        $headerText = [string]$Value
        $styleAttribute = if ($BoldHeader) { ' s="3"' } else { '' }
        return [pscustomobject]@{
            Xml          = '<c r="{0}" t="inlineStr"{1}><is><t xml:space="preserve">{2}</t></is></c>' -f $cellReference, $styleAttribute, (& $escapeText $headerText)
            DisplayWidth = [double]$headerText.Length
        }
    }

    $resolvedValue = ConvertFrom-OracleProviderValue -Value $Value

    if ($null -eq $resolvedValue) {
        if ([string]::IsNullOrEmpty($NullValue)) {
            return [pscustomobject]@{
                Xml          = '<c r="{0}" />' -f $cellReference
                DisplayWidth = 0.0
            }
        }

        $resolvedValue = $NullValue
    }

    if ($resolvedValue -is [datetimeoffset]) {
        $resolvedValue = $resolvedValue.DateTime
    }

    if ($resolvedValue -is [datetime]) {
        $styleIndex = if ($resolvedValue.TimeOfDay.Ticks -eq 0) { 1 } else { 2 }
        $displayText = if ($styleIndex -eq 1) {
            $resolvedValue.ToString('yyyy-MM-dd', $culture)
        }
        else {
            $resolvedValue.ToString('yyyy-MM-dd HH:mm:ss', $culture)
        }

        return [pscustomobject]@{
            Xml          = '<c r="{0}" s="{1}"><v>{2}</v></c>' -f $cellReference, $styleIndex, $resolvedValue.ToOADate().ToString($culture)
            DisplayWidth = [double]$displayText.Length
        }
    }

    if ($resolvedValue -is [bool]) {
        return [pscustomobject]@{
            Xml          = '<c r="{0}" t="b"><v>{1}</v></c>' -f $cellReference, $(if ($resolvedValue) { 1 } else { 0 })
            DisplayWidth = [double]([string]$resolvedValue).Length
        }
    }

    $typeCode = [System.Type]::GetTypeCode($resolvedValue.GetType())
    if ($typeCode -in @(
            [System.TypeCode]::Byte,
            [System.TypeCode]::SByte,
            [System.TypeCode]::Int16,
            [System.TypeCode]::UInt16,
            [System.TypeCode]::Int32,
            [System.TypeCode]::UInt32,
            [System.TypeCode]::Int64,
            [System.TypeCode]::UInt64,
            [System.TypeCode]::Single,
            [System.TypeCode]::Double,
            [System.TypeCode]::Decimal
        )) {
        if (($resolvedValue -is [double] -or $resolvedValue -is [single]) -and ([double]::IsNaN([double]$resolvedValue) -or [double]::IsInfinity([double]$resolvedValue))) {
            $resolvedValue = [string]$resolvedValue
        }
        else {
            $numberText = ([System.IFormattable]$resolvedValue).ToString($null, $culture)
            return [pscustomobject]@{
                Xml          = '<c r="{0}"><v>{1}</v></c>' -f $cellReference, $numberText
                DisplayWidth = [double]$numberText.Length
            }
        }
    }

    $textValue = if ($resolvedValue -is [byte[]]) {
        [System.Convert]::ToBase64String($resolvedValue)
    }
    else {
        [string]$resolvedValue
    }

    return [pscustomobject]@{
        Xml          = '<c r="{0}" t="inlineStr"><is><t xml:space="preserve">{1}</t></is></c>' -f $cellReference, (& $escapeText $textValue)
        DisplayWidth = [double]$textValue.Length
    }
}
