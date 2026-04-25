function Invoke-OracleExcelTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName,

        [Parameter()]
        [string]$Sql,

        [Parameter()]
        [string]$SqlPath,

        [Parameter()]
        $Parameters,

        [Parameter(Mandatory)]
        [string]$TemplatePath,

        [Parameter(Mandatory)]
        [string]$OutputDirectory,

        [Parameter(Mandatory)]
        [string]$OutputFileNameTemplate,

        [Parameter()]
        [string]$WorksheetName,

        [Parameter()]
        [hashtable]$CellMap,

        [Parameter()]
        [scriptblock]$EachWorkbook,

        [Parameter()]
        [switch]$AutoFit,

        [Parameter()]
        [string]$RunMacro,

        [Parameter()]
        [ValidateSet('Workbook', 'Pdf')]
        [string]$SaveAs = 'Workbook',

        [Parameter()]
        [switch]$ContinueOnError,

        [Parameter()]
        [switch]$Visible
    )

    Set-StrictMode -Version Latest

    if ($PSBoundParameters.ContainsKey('Sql') -eq $PSBoundParameters.ContainsKey('SqlPath')) {
        throw 'Provide either -Sql or -SqlPath, but not both.'
    }

    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        throw "Template file not found: $TemplatePath"
    }

    if ($PSBoundParameters.ContainsKey('SqlPath')) {
        if (-not (Test-Path -LiteralPath $SqlPath -PathType Leaf)) {
            throw "SQL file not found: $SqlPath"
        }
        $Sql = Get-Content -LiteralPath $SqlPath -Raw
    }

    if ([string]::IsNullOrWhiteSpace($Sql)) {
        throw 'SQL query text cannot be empty.'
    }

    if (-not $CellMap -and -not $EachWorkbook) {
        throw 'Provide -CellMap, -EachWorkbook, or both.'
    }

    $resolvedTemplatePath = (Resolve-Path -LiteralPath $TemplatePath).ProviderPath

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }
    $resolvedOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath

    $queryParameters = @{
        ProfileName = $ProfileName
        Sql         = $Sql
    }
    if ($PSBoundParameters.ContainsKey('Parameters')) {
        $queryParameters.Parameters = $Parameters
    }

    $rows = @(Invoke-OracleQuery @queryParameters)

    $excel = $null
    $completed = New-Object System.Collections.Generic.List[object]
    $rowNumber = 0

    function Resolve-TemplateText {
        param(
            [Parameter(Mandatory)]
            [string]$Template,

            [Parameter(Mandatory)]
            $Row,

            [Parameter(Mandatory)]
            [int]$RowNumber
        )

        $resolved = $Template.Replace('{RowNumber}', [string]$RowNumber)

        foreach ($property in $Row.PSObject.Properties) {
            $token = '{' + $property.Name + '}'
            if ($resolved.Contains($token)) {
                $safeValue = [string]$property.Value
                foreach ($invalidChar in [System.IO.Path]::GetInvalidFileNameChars()) {
                    $safeValue = $safeValue.Replace([string]$invalidChar, '_')
                }
                $resolved = $resolved.Replace($token, $safeValue)
            }
        }

        return $resolved
    }

    function Release-ComObject {
        param(
            [Parameter()]
            $ComObject
        )

        if ($null -ne $ComObject -and [System.Runtime.InteropServices.Marshal]::IsComObject($ComObject)) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($ComObject)
        }
    }

    function ConvertTo-ExcelComValue {
        param(
            [AllowNull()]
            $Value
        )

        if ($null -eq $Value -or $Value -is [System.DBNull]) {
            return $null
        }

        $type = $Value.GetType()
        $fullName = $type.FullName

        if ($fullName -like 'Oracle.ManagedDataAccess.Types.*' -or $fullName -like 'Oracle.ManagedDataAccess.Client.Oracle*') {
            $isNullProperty = $type.GetProperty('IsNull')
            if ($isNullProperty) {
                try {
                    if ([bool]$isNullProperty.GetValue($Value, $null)) {
                        return $null
                    }
                }
                catch {
                }
            }

            $valueProperty = $type.GetProperty('Value')
            if ($valueProperty) {
                try {
                    $Value = $valueProperty.GetValue($Value, $null)
                }
                catch {
                }
            }
        }

        if ($Value -is [datetimeoffset]) {
            return $Value.DateTime.ToOADate()
        }

        if ($Value -is [datetime]) {
            return $Value.ToOADate()
        }

        if ($Value -is [decimal]) {
            if ($Value -eq [decimal]::Truncate($Value)) {
                if ($Value -ge [int]::MinValue -and $Value -le [int]::MaxValue) {
                    return [int]$Value
                }
                if ($Value -ge [long]::MinValue -and $Value -le [long]::MaxValue) {
                    return [long]$Value
                }
            }

            return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        }

        if ($Value -is [double] -or $Value -is [single]) {
            return ([double]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        }

        if ($Value -is [byte[]]) {
            return [System.Convert]::ToBase64String($Value)
        }

        return $Value
    }

    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = [bool]$Visible
        $excel.DisplayAlerts = $false
        $excel.EnableEvents = $false
        $excel.AskToUpdateLinks = $false

        foreach ($row in $rows) {
            $rowNumber++
            $workbook = $null
            $worksheet = $null
            $outputPath = $null
            $sw = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $outputFileName = Resolve-TemplateText -Template $OutputFileNameTemplate -Row $row -RowNumber $rowNumber
                $outputPath = Join-Path -Path $resolvedOutputDirectory -ChildPath $outputFileName

                $workbook = $excel.Workbooks.Open($resolvedTemplatePath, 0, $true)
                $worksheet = if ($WorksheetName) {
                    $workbook.Worksheets.Item($WorksheetName)
                }
                else {
                    $workbook.Worksheets.Item(1)
                }

                if ($CellMap) {
                    foreach ($cellAddress in $CellMap.Keys) {
                        $propertyName = [string]$CellMap[$cellAddress]
                        $property = $row.PSObject.Properties[$propertyName]
                        if (-not $property) {
                            throw "Column [$propertyName] was not found in the query result row."
                        }

                        $cellAddressText = [string]$cellAddress
                        $excelValue = ConvertTo-ExcelComValue -Value $property.Value
                        $range = $null
                        try {
                            $range = $worksheet.Range($cellAddressText, $cellAddressText)
                            [void]$range.GetType().InvokeMember(
                                'Value2',
                                [System.Reflection.BindingFlags]::SetProperty,
                                $null,
                                $range,
                                @($excelValue),
                                [System.Globalization.CultureInfo]::InvariantCulture
                            )
                        }
                        catch {
                            $valueType = if ($null -eq $excelValue) { '<null>' } else { $excelValue.GetType().FullName }
                            throw "Failed writing column [$propertyName] to cell [$cellAddressText] as [$valueType]. $($_.Exception.Message)"
                        }
                        finally {
                            if ($null -ne $range -and [System.Runtime.InteropServices.Marshal]::IsComObject($range)) {
                                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($range)
                            }
                        }
                    }
                }

                if ($EachWorkbook) {
                    & $EachWorkbook $workbook $worksheet $row
                }

                if ($RunMacro) {
                    [void]$excel.Run($RunMacro)
                }

                if ($AutoFit) {
                    $usedRange = $null
                    $usedColumns = $null
                    $usedRows = $null
                    try {
                        $usedRange = $worksheet.UsedRange
                        $usedColumns = $usedRange.Columns
                        $usedRows = $usedRange.Rows
                        [void]$usedColumns.AutoFit()
                        [void]$usedRows.AutoFit()
                    }
                    finally {
                        Release-ComObject -ComObject $usedRows
                        Release-ComObject -ComObject $usedColumns
                        Release-ComObject -ComObject $usedRange
                    }
                }

                if ($SaveAs -eq 'Pdf') {
                    $xlTypePdf = 0
                    [void]$workbook.ExportAsFixedFormat($xlTypePdf, $outputPath)
                }
                else {
                    [void]$workbook.SaveAs($outputPath)
                }

                $sw.Stop()
                $fileSizeBytes = if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
                    (Get-Item -LiteralPath $outputPath).Length
                }
                else {
                    0
                }

                $result = [pscustomobject]@{
                    Success       = $true
                    Operation     = 'Invoke-OracleExcelTemplate'
                    ProfileName   = $ProfileName
                    RowNumber     = $rowNumber
                    OutputPath    = $outputPath
                    SaveAs        = $SaveAs
                    FileSizeBytes = $fileSizeBytes
                    ElapsedMs     = $sw.ElapsedMilliseconds
                }
                $result.PSObject.TypeNames.Insert(0, 'PSOracleTools.Optional.ExcelTemplateResult')
                $completed.Add($result) | Out-Null
            }
            catch {
                $sw.Stop()
                $result = [pscustomobject]@{
                    Success      = $false
                    Operation    = 'Invoke-OracleExcelTemplate'
                    ProfileName  = $ProfileName
                    RowNumber    = $rowNumber
                    OutputPath   = $outputPath
                    SaveAs       = $SaveAs
                    ErrorType    = $_.Exception.GetType().FullName
                    ErrorMessage = $_.Exception.Message
                    ElapsedMs    = $sw.ElapsedMilliseconds
                }
                $result.PSObject.TypeNames.Insert(0, 'PSOracleTools.Optional.ExcelTemplateResult')
                $completed.Add($result) | Out-Null
                if (-not $ContinueOnError) {
                    throw
                }
            }
            finally {
                if ($workbook) {
                    $workbook.Close($false)
                }

                Release-ComObject -ComObject $worksheet
                Release-ComObject -ComObject $workbook
            }
        }
    }
    finally {
        if ($excel) {
            $excel.Quit()
        }

        Release-ComObject -ComObject $excel
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }

    return $completed.ToArray()
}
