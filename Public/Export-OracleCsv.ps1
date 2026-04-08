<#
.SYNOPSIS
Exports query results to a CSV file.

.DESCRIPTION
Runs a query and writes the resulting rows to a UTF-8 CSV file.
This is a convenience wrapper around Export-OracleDelimitedFile with CSV-friendly defaults:
comma delimiter, header row included, and all fields quoted.

.PARAMETER Sql
SQL query text to export.

.PARAMETER Path
Output CSV file path.

.PARAMETER NullValue
Replacement text for null values.

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

        [Parameter(Mandatory)]
        [string]$Sql,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$NullValue = '',

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

    $invokeParams = @{
        Sql            = $Sql
        Path           = $Path
        Delimiter      = ','
        IncludeHeader  = $true
        QuoteAll       = $true
        NullValue      = $NullValue
        CommandTimeout = $CommandTimeout
    }

    if ($PSBoundParameters.ContainsKey('Parameters')) {
        $invokeParams.Parameters = $Parameters
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
