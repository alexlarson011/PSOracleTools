<#
.SYNOPSIS
Exports query results to an Excel workbook.

.DESCRIPTION
Runs a query and writes the resulting rows to a valid `.xlsx` workbook without requiring Microsoft Excel.
Supports raw connection strings, PSCredential input, or saved credential names.

.PARAMETER Sql
SQL query text to export.

.PARAMETER Path
Output workbook path.

.PARAMETER WorksheetName
Worksheet name written into the workbook.

.PARAMETER IncludeHeader
Includes a header row with column names. Defaults to $true.

.PARAMETER BoldHeader
Renders the header row in bold. Defaults to $false.

.PARAMETER NullValue
Replacement text for null values. The default leaves null cells blank.

.PARAMETER AutoFilter
Adds an Excel autofilter to the header row. Defaults to $false.

.PARAMETER FreezeHeaderRow
Freezes the first row when headers are included. Defaults to $false.

.PARAMETER AutoSizeColumns
Sizes columns based on the exported content. Defaults to $true.

.PARAMETER MaxColumnWidth
Maximum width used when auto-sizing columns.

.PARAMETER Parameters
Optional bind parameters supplied as a hashtable or OracleParameter objects.

.PARAMETER CommandTimeout
Command timeout in seconds.

.PARAMETER ProfileName
Saved connection profile name.

.PARAMETER CredentialStorePath
Optional custom path to the credential store JSON file.

.PARAMETER Log
Writes operational log entries to the information stream.

.PARAMETER LogPath
Optional log file path.

.PARAMETER LogSql
Includes SQL text in log entries.

.PARAMETER LogParameters
Includes parameter names and types in log entries.

.EXAMPLE
Export-OracleExcel -ProfileName 'ProdLow' -Sql 'select movie_id, movie_nm from ps_tools.movies' -Path '.\output\movies.xlsx'

Exports query results to a native Excel workbook using a saved connection profile.
#>
function Export-OracleExcel {
    [CmdletBinding(DefaultParameterSetName = 'ByConnectionString')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByConnectionString')]
        [string]$ConnectionString,

        [Parameter(Mandatory, ParameterSetName = 'ByCredential')]
        [PSCredential]$Credential,

        [Parameter(Mandatory, ParameterSetName = 'ByCredential')]
        [string]$DataSource,

        [Parameter(Mandatory, ParameterSetName = 'ByCredentialName')]
        [string]$CredentialName,

        [Parameter(Mandatory, ParameterSetName = 'ByCredentialName')]
        [string]$CredentialDataSource,

        [Parameter(Mandatory, ParameterSetName = 'ByProfileName')]
        [string]$ProfileName,

        [Parameter(Mandatory)]
        [string]$Sql,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$WorksheetName = 'Results',

        [Parameter()]
        [bool]$IncludeHeader = $true,

        [Parameter()]
        [bool]$BoldHeader = $false,

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
        [int]$MaxColumnWidth = 60,

        [Parameter()]
        $Parameters,

        [Parameter()]
        [int]$CommandTimeout = 300,

        [Parameter()]
        [string]$CredentialStorePath,

        [Parameter()]
        [string]$ProfileStorePath,

        [Parameter()]
        [switch]$Log,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [switch]$LogSql,

        [Parameter()]
        [switch]$LogParameters
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $connection = $null
    $command = $null
    $reader = $null
    $targetDataSource = $null
    $resolvedProfile = $null
    $result = $null

    try {
        switch ($PSCmdlet.ParameterSetName) {
            'ByConnectionString' {
                $cs = $ConnectionString
            }
            'ByCredential' {
                $targetDataSource = $DataSource
                $cs = New-OracleConnectionString -DataSource $DataSource -UserId $Credential.UserName -Password ($Credential.GetNetworkCredential().Password)
            }
            'ByCredentialName' {
                $resolvedCredential = Resolve-OracleCredential -CredentialName $CredentialName -CredentialStorePath $CredentialStorePath
                $targetDataSource = $CredentialDataSource
                $cs = New-OracleConnectionString -DataSource $CredentialDataSource -UserId $resolvedCredential.UserName -Password ($resolvedCredential.GetNetworkCredential().Password)
            }
            'ByProfileName' {
                $resolvedProfile = Resolve-OracleConnectionProfile -ProfileName $ProfileName -ProfileStorePath $ProfileStorePath
                if (-not $PSBoundParameters.ContainsKey('CredentialStorePath') -and $resolvedProfile.CredentialStorePath) {
                    $CredentialStorePath = [string]$resolvedProfile.CredentialStorePath
                }
                if (-not $PSBoundParameters.ContainsKey('CommandTimeout') -and $resolvedProfile.CommandTimeout) {
                    $CommandTimeout = [int]$resolvedProfile.CommandTimeout
                }
                if (-not $PSBoundParameters.ContainsKey('LogPath') -and $resolvedProfile.LogPath) {
                    $LogPath = [string]$resolvedProfile.LogPath
                }
                if (-not $PSBoundParameters.ContainsKey('LogSql') -and $resolvedProfile.LogSql) {
                    $LogSql = [bool]$resolvedProfile.LogSql
                }
                if (-not $PSBoundParameters.ContainsKey('LogParameters') -and $resolvedProfile.LogParameters) {
                    $LogParameters = [bool]$resolvedProfile.LogParameters
                }

                $resolvedCredential = Resolve-OracleCredential -CredentialName ([string]$resolvedProfile.CredentialName) -CredentialStorePath $CredentialStorePath
                $targetDataSource = [string]$resolvedProfile.DataSource
                $cs = New-OracleConnectionString -DataSource $targetDataSource -UserId $resolvedCredential.UserName -Password ($resolvedCredential.GetNetworkCredential().Password)
            }
        }

        $normalizedSql = Normalize-OracleCommandText -Text $Sql -Mode Sql

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Export-OracleExcel started; DataSource={0}; OutputPath={1}; WorksheetName={2}; CommandTimeout={3}" -f $targetDataSource, $Path, $WorksheetName, $CommandTimeout)
            if ($LogSql) {
                Write-OracleLog -Path $LogPath -Message ("Export-OracleExcel SQL: {0}" -f $normalizedSql)
            }
            if ($LogParameters) {
                Write-OracleLog -Path $LogPath -Message ("Export-OracleExcel Parameters: {0}" -f ((Get-OracleParameterSummary -Parameters $Parameters) -join ', '))
            }
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText $normalizedSql -CommandTimeout $CommandTimeout
        Add-OracleParameters -Command $command -Parameters $Parameters

        $reader = $command.ExecuteReader()
        $result = Write-ExcelWorkbookFromDataReader -Reader $reader -Path $Path -WorksheetName $WorksheetName -IncludeHeader $IncludeHeader -BoldHeader $BoldHeader -NullValue $NullValue -AutoFilter $AutoFilter -FreezeHeaderRow $FreezeHeaderRow -AutoSizeColumns $AutoSizeColumns -MaxColumnWidth $MaxColumnWidth

        $sw.Stop()

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Export-OracleExcel succeeded; DataSource={0}; OutputPath={1}; RowCount={2}; ElapsedMs={3}" -f $connection.DataSource, $Path, $result.RowCount, $sw.ElapsedMilliseconds)
        }

        [pscustomobject]@{
            Success       = $true
            Path          = $Path
            WorksheetName = $result.WorksheetName
            RowCount      = $result.RowCount
            ColumnCount   = $result.ColumnCount
            ElapsedMs     = $sw.ElapsedMilliseconds
        }
    }
    catch {
        $sw.Stop()
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Export-OracleExcel failed; DataSource={0}; OutputPath={1}; ElapsedMs={2}; Error={3}" -f $targetDataSource, $Path, $sw.ElapsedMilliseconds, (Get-OracleExceptionMessage -Exception $_.Exception))
        }
        throw
    }
    finally {
        Close-OracleResource -Object $reader
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
