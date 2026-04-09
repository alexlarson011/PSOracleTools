function ConvertTo-ExcelWorksheetName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name = 'Results'
    )

    $worksheetName = if ([string]::IsNullOrWhiteSpace($Name)) {
        'Results'
    }
    else {
        $Name.Trim()
    }

    $worksheetName = $worksheetName -replace '[\\\/\*\?\:\[\]]', '_'
    $worksheetName = $worksheetName.Trim("'")

    if ([string]::IsNullOrWhiteSpace($worksheetName)) {
        $worksheetName = 'Results'
    }

    if ($worksheetName.Length -gt 31) {
        $worksheetName = $worksheetName.Substring(0, 31)
    }

    return $worksheetName
}
