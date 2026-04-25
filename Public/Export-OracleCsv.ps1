<#
.SYNOPSIS
Exports query results to a CSV file.

.DESCRIPTION
Runs a query and writes the resulting rows to a UTF-8 CSV file.
This is a convenience wrapper around Export-OracleDelimitedFile with CSV-friendly defaults:
comma delimiter, header row included, and all fields quoted.

.PARAMETER Sql
SQL query text to export. Use either -Sql or -SqlPath.

.PARAMETER SqlPath
Path to a file containing SQL query text to export. Use either -Sql or -SqlPath.

.PARAMETER Path
Output CSV file path.

.PARAMETER NullValue
Replacement text for null values.

.PARAMETER DateFormat
Optional .NET date format string for date-only values in CSV output.

.PARAMETER DateTimeFormat
Optional .NET date/time format string for date/time values in CSV output.

.PARAMETER Culture
Culture name used for CSV number and date formatting.

.PARAMETER Parameters
Optional bind parameters supplied as a hashtable or OracleParameter objects.

.PARAMETER NoClobber
Prevents overwriting an existing output file.

.PARAMETER Force
Allows overwriting an existing output file even when -NoClobber is specified.

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
Export-OracleCsv -ProfileName 'ProdLow' -Sql 'select movie_id, movie_nm from ps_tools.movies' -Path '.\output\movies.csv'

Exports query results to a CSV file using a saved connection profile.
#>
function Export-OracleCsv {
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

        [Parameter()]
        [string]$Sql,

        [Parameter()]
        [string]$SqlPath,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$NullValue = '',

        [Parameter()]
        [string]$DateFormat,

        [Parameter()]
        [string]$DateTimeFormat,

        [Parameter()]
        [string]$Culture,

        [Parameter()]
        $Parameters,

        [Parameter()]
        [switch]$NoClobber,

        [Parameter()]
        [switch]$Force,

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

    $invokeParams = @{
        Path           = $Path
        Delimiter      = ','
        IncludeHeader  = $true
        QuoteAll       = $true
        NullValue      = $NullValue
        CommandTimeout = $CommandTimeout
    }

    if ($PSBoundParameters.ContainsKey('Sql')) {
        $invokeParams.Sql = $Sql
    }
    if ($PSBoundParameters.ContainsKey('SqlPath')) {
        $invokeParams.SqlPath = $SqlPath
    }
    if ($PSBoundParameters.ContainsKey('DateFormat')) {
        $invokeParams.DateFormat = $DateFormat
    }
    if ($PSBoundParameters.ContainsKey('DateTimeFormat')) {
        $invokeParams.DateTimeFormat = $DateTimeFormat
    }
    if ($PSBoundParameters.ContainsKey('Culture')) {
        $invokeParams.Culture = $Culture
    }
    if ($PSBoundParameters.ContainsKey('Parameters')) {
        $invokeParams.Parameters = $Parameters
    }
    if ($PSBoundParameters.ContainsKey('NoClobber')) {
        $invokeParams.NoClobber = $NoClobber
    }
    if ($PSBoundParameters.ContainsKey('Force')) {
        $invokeParams.Force = $Force
    }
    if ($PSBoundParameters.ContainsKey('CredentialStorePath')) {
        $invokeParams.CredentialStorePath = $CredentialStorePath
    }
    if ($PSBoundParameters.ContainsKey('ProfileStorePath')) {
        $invokeParams.ProfileStorePath = $ProfileStorePath
    }
    if ($PSBoundParameters.ContainsKey('Log')) {
        $invokeParams.Log = $Log
    }
    if ($PSBoundParameters.ContainsKey('LogPath')) {
        $invokeParams.LogPath = $LogPath
    }
    if ($PSBoundParameters.ContainsKey('LogSql')) {
        $invokeParams.LogSql = $LogSql
    }
    if ($PSBoundParameters.ContainsKey('LogParameters')) {
        $invokeParams.LogParameters = $LogParameters
    }

    switch ($PSCmdlet.ParameterSetName) {
        'ByConnectionString' {
            $invokeParams.ConnectionString = $ConnectionString
        }
        'ByCredential' {
            $invokeParams.Credential = $Credential
            $invokeParams.DataSource = $DataSource
        }
        'ByCredentialName' {
            $invokeParams.CredentialName = $CredentialName
            $invokeParams.CredentialDataSource = $CredentialDataSource
        }
        'ByProfileName' {
            $invokeParams.ProfileName = $ProfileName
        }
    }

    return Export-OracleDelimitedFile @invokeParams
}
