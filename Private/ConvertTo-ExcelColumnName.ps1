function ConvertTo-ExcelColumnName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 16384)]
        [int]$Index
    )

    $name = ''
    $workingIndex = $Index

    while ($workingIndex -gt 0) {
        $workingIndex--
        $name = ([char](65 + ($workingIndex % 26))).ToString() + $name
        $workingIndex = [int][math]::Floor($workingIndex / 26)
    }

    return $name
}
