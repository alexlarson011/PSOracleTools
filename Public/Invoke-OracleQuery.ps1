<#
.SYNOPSIS
Runs a query and returns result rows.

.DESCRIPTION
Executes a SQL query and converts the Oracle data reader into PowerShell objects.
Supports raw connection strings, PSCredential input, or saved credential names.
Optional logging can include lifecycle entries, SQL text, and parameter summaries.

.PARAMETER Sql
SQL query text to execute.

.PARAMETER Parameters
Optional bind parameters supplied as a hashtable or OracleParameter objects.

.PARAMETER CommandTimeout
Command timeout in seconds.

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
Invoke-OracleQuery -Credential $cred -DataSource 'mydb_low' -Sql 'select movie_id, movie_nm from ps_tools.movies'

Runs a query and returns rows as PowerShell objects.

.EXAMPLE
$p = New-OracleParameter -Name 'movie_id' -Value 1 -OracleDbType Int32
Invoke-OracleQuery -CredentialName 'ProdLow' -CredentialDataSource 'mydb_low' -Sql 'select movie_id, movie_nm from ps_tools.movies where movie_id = :movie_id' -Parameters @($p)

Runs a parameterized query using a saved credential.
#>
function Invoke-OracleQuery {
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

        [Parameter(Mandatory)]
        [string]$Sql,

        [Parameter()]
        $Parameters,

        [Parameter()]
        [int]$CommandTimeout = 300,

        [Parameter()]
        [string]$CredentialStorePath,

        [Parameter()]
        [switch]$Log,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [switch]$LogSql,

        [Parameter()]
        [switch]$LogParameters
    )

    $connection = $null
    $command = $null
    $reader = $null
    $targetDataSource = $null
    $rowCount = 0

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
        }

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleQuery started; DataSource={0}; CommandTimeout={1}" -f $targetDataSource, $CommandTimeout)
            if ($LogSql) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OracleQuery SQL: {0}" -f $Sql)
            }
            if ($LogParameters) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OracleQuery Parameters: {0}" -f ((Get-OracleParameterSummary -Parameters $Parameters) -join ', '))
            }
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText $Sql -CommandTimeout $CommandTimeout
        Add-OracleParameters -Command $command -Parameters $Parameters

        $reader = $command.ExecuteReader()
        $result = ConvertFrom-OracleDataReader -Reader $reader
        $rowCount = @($result).Count

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleQuery succeeded; DataSource={0}; RowCount={1}" -f $connection.DataSource, $rowCount)
        }

        return $result
    }
    catch {
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Invoke-OracleQuery failed; DataSource={0}; Error={1}" -f $targetDataSource, (Get-OracleExceptionMessage -Exception $_.Exception))
        }
        throw
    }
    finally {
        Close-OracleResource -Object $reader
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
