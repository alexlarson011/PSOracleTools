function Write-ExcelWorkbookFromDataReader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Reader,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [bool]$IncludeHeader = $true,

        [Parameter()]
        [bool]$BoldHeader = $false,

        [Parameter()]
        [string]$WorksheetName = 'Results',

        [Parameter()]
        [string]$NullValue = '',

        [Parameter()]
        [bool]$AutoFilter = $false,

        [Parameter()]
        [bool]$FreezeHeaderRow = $false,

        [Parameter()]
        [bool]$AutoSizeColumns = $true,

        [Parameter()]
        [ValidateRange(1, 255)]
        [int]$MaxColumnWidth = 60
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    if (-not $IncludeHeader) {
        $AutoFilter = $false
        $FreezeHeaderRow = $false
    }

    $worksheetName = ConvertTo-ExcelWorksheetName -Name $WorksheetName
    $columnCount = [int]$Reader.FieldCount
    $widths = New-Object 'double[]' $columnCount
    $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('PSOracleTools-xlsx-' + [guid]::NewGuid().ToString('N'))
    $sheetDataPath = Join-Path -Path $tempRoot -ChildPath 'sheetData.xml'
    $worksheetPath = Join-Path -Path $tempRoot -ChildPath 'sheet1.xml'
    $packagePath = Join-Path -Path $tempRoot -ChildPath 'workbook.xlsx'
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $sheetDataWriter = $null
    $worksheetWriter = $null
    $zip = $null
    $rowCount = 0
    $lastRowIndex = 0

    try {
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        $sheetDataWriter = New-Object System.IO.StreamWriter($sheetDataPath, $false, $utf8NoBom)

        if ($IncludeHeader) {
            $lastRowIndex = 1
            $sheetDataWriter.Write('<row r="1">')
            for ($i = 0; $i -lt $columnCount; $i++) {
                $headerCell = ConvertTo-ExcelCellXml -ColumnIndex ($i + 1) -RowIndex 1 -Value $Reader.GetName($i) -Header -BoldHeader $BoldHeader
                $sheetDataWriter.Write($headerCell.Xml)
                $widths[$i] = [math]::Max($widths[$i], $headerCell.DisplayWidth)
            }
            $sheetDataWriter.Write('</row>')
        }

        while ($Reader.Read()) {
            $rowCount++
            $lastRowIndex++
            $sheetDataWriter.Write('<row r="{0}">' -f $lastRowIndex)

            for ($i = 0; $i -lt $columnCount; $i++) {
                $value = if ($Reader.IsDBNull($i)) { $null } else { $Reader.GetValue($i) }
                $cell = ConvertTo-ExcelCellXml -ColumnIndex ($i + 1) -RowIndex $lastRowIndex -Value $value -NullValue $NullValue
                $sheetDataWriter.Write($cell.Xml)
                $widths[$i] = [math]::Max($widths[$i], $cell.DisplayWidth)
            }

            $sheetDataWriter.Write('</row>')
        }

        $sheetDataWriter.Flush()
        Close-OracleResource -Object $sheetDataWriter
        $sheetDataWriter = $null

        $worksheetWriter = New-Object System.IO.StreamWriter($worksheetPath, $false, $utf8NoBom)
        $worksheetWriter.Write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        $worksheetWriter.Write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')

        $lastColumnName = if ($columnCount -gt 0) { ConvertTo-ExcelColumnName -Index $columnCount } else { 'A' }
        $dimensionReference = if ($lastRowIndex -gt 0 -and $columnCount -gt 0) {
            'A1:{0}{1}' -f $lastColumnName, $lastRowIndex
        }
        else {
            'A1'
        }
        $worksheetWriter.Write('<dimension ref="{0}"/>' -f $dimensionReference)

        if ($FreezeHeaderRow) {
            $worksheetWriter.Write('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/></sheetView></sheetViews>')
        }

        $worksheetWriter.Write('<sheetFormatPr defaultRowHeight="15"/>')

        if ($AutoSizeColumns -and $columnCount -gt 0) {
            $worksheetWriter.Write('<cols>')
            for ($i = 0; $i -lt $columnCount; $i++) {
                $displayWidth = [math]::Min([math]::Max($widths[$i] + 2, 8.43), $MaxColumnWidth)
                $columnWidthXml = '<col min="{0}" max="{0}" width="{1}" customWidth="1"/>' -f ($i + 1), $displayWidth.ToString([System.Globalization.CultureInfo]::InvariantCulture)
                $worksheetWriter.Write($columnWidthXml)
            }
            $worksheetWriter.Write('</cols>')
        }

        $worksheetWriter.Write('<sheetData>')
        foreach ($line in [System.IO.File]::ReadLines($sheetDataPath)) {
            $worksheetWriter.Write($line)
        }
        $worksheetWriter.Write('</sheetData>')

        if ($AutoFilter -and $columnCount -gt 0 -and $lastRowIndex -gt 0) {
            $autoFilterXml = '<autoFilter ref="A1:{0}{1}"/>' -f $lastColumnName, $lastRowIndex
            $worksheetWriter.Write($autoFilterXml)
        }

        $worksheetWriter.Write('</worksheet>')
        $worksheetWriter.Flush()
        Close-OracleResource -Object $worksheetWriter
        $worksheetWriter = $null

        $zip = [System.IO.Compression.ZipFile]::Open($packagePath, [System.IO.Compression.ZipArchiveMode]::Create)

        $contentTypes = $zip.CreateEntry('[Content_Types].xml')
        $contentTypesWriter = New-Object System.IO.StreamWriter($contentTypes.Open(), $utf8NoBom)
        $contentTypesWriter.Write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        $contentTypesWriter.Write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>')
        $contentTypesWriter.Dispose()

        $rootRels = $zip.CreateEntry('_rels/.rels')
        $rootRelsWriter = New-Object System.IO.StreamWriter($rootRels.Open(), $utf8NoBom)
        $rootRelsWriter.Write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        $rootRelsWriter.Write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        $rootRelsWriter.Dispose()

        $workbookEntry = $zip.CreateEntry('xl/workbook.xml')
        $workbookWriter = New-Object System.IO.StreamWriter($workbookEntry.Open(), $utf8NoBom)
        $workbookWriter.Write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        $workbookWriter.Write('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView xWindow="0" yWindow="0" windowWidth="28800" windowHeight="17400"/></bookViews><sheets><sheet name="{0}" sheetId="1" r:id="rId1"/></sheets></workbook>' -f [System.Security.SecurityElement]::Escape($worksheetName))
        $workbookWriter.Dispose()

        $workbookRelsEntry = $zip.CreateEntry('xl/_rels/workbook.xml.rels')
        $workbookRelsWriter = New-Object System.IO.StreamWriter($workbookRelsEntry.Open(), $utf8NoBom)
        $workbookRelsWriter.Write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        $workbookRelsWriter.Write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>')
        $workbookRelsWriter.Dispose()

        $stylesEntry = $zip.CreateEntry('xl/styles.xml')
        $stylesWriter = New-Object System.IO.StreamWriter($stylesEntry.Open(), $utf8NoBom)
        $stylesWriter.Write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        $stylesWriter.Write('<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font><font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="22" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles><dxfs count="0"/><tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/></styleSheet>')
        $stylesWriter.Dispose()

        $worksheetEntry = $zip.CreateEntry('xl/worksheets/sheet1.xml')
        $worksheetStream = $worksheetEntry.Open()
        $worksheetFileStream = [System.IO.File]::OpenRead($worksheetPath)
        $worksheetFileStream.CopyTo($worksheetStream)
        $worksheetFileStream.Dispose()
        $worksheetStream.Dispose()

        Close-OracleResource -Object $zip
        $zip = $null

        if (Test-Path -Path $Path) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }

        Move-Item -LiteralPath $packagePath -Destination $Path -Force -ErrorAction Stop

        [pscustomobject]@{
            Path          = $Path
            RowCount      = $rowCount
            ColumnCount   = $columnCount
            WorksheetName = $worksheetName
        }
    }
    finally {
        Close-OracleResource -Object $sheetDataWriter
        Close-OracleResource -Object $worksheetWriter
        Close-OracleResource -Object $zip

        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
