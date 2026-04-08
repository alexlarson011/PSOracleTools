<#
.SYNOPSIS
Executes SQL or PL/SQL from a file.

.DESCRIPTION
Reads a .sql file from disk and executes its contents as a non-query Oracle command.
This is intended for DDL, DML, and PL/SQL scripts used in automation.
Supports raw connection strings, PSCredential input, saved credential names, or saved connection profiles.

.PARAMETER Path
Path to the SQL file to execute.

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

.EXAMPLE
Invoke-OracleSqlFile -ProfileName 'ProdLow' -Path 'C:\Scripts\refresh_movies.sql'

Executes a SQL file using a saved connection profile.
#>
function Invoke-OracleSqlFile {
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
        [string]$Path,

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
        [switch]$LogSql
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "SQL file not found: $Path"
    }

    $sqlText = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($sqlText)) {
        throw "SQL file is empty: $Path"
    }

    $trimmedSql = $sqlText.Trim()

    if ($trimmedSql.EndsWith('/')) {
        $trimmedSql = $trimmedSql.TrimEnd('/').TrimEnd()
    }

    if ($Log -or $LogPath) {
        Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile reading script: {0}" -f $Path)
    }

    $invokeParams = @{
        Sql = $trimmedSql
    }

    if ($PSBoundParameters.ContainsKey('CommandTimeout')) {
        $invokeParams.CommandTimeout = $CommandTimeout
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
            if ($CredentialStorePath) {
                $invokeParams.CredentialStorePath = $CredentialStorePath
            }
        }
        'ByProfileName' {
            $invokeParams.ProfileName = $ProfileName
            if ($ProfileStorePath) {
                $invokeParams.ProfileStorePath = $ProfileStorePath
            }
            if ($CredentialStorePath) {
                $invokeParams.CredentialStorePath = $CredentialStorePath
            }
        }
    }

    return Invoke-OracleNonQuery @invokeParams
}
