<#
.SYNOPSIS
Runs a SQL statement that does not return rows.

.DESCRIPTION
Executes DML or other non-query SQL and returns rows affected plus elapsed time.
Supports raw connection strings, PSCredential input, or saved credential names.

.PARAMETER Sql
SQL text to execute.

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
Invoke-OracleNonQuery -Credential $cred -DataSource 'mydb_low' -Sql 'delete from ps_tools.movies where movie_id = :movie_id' -Parameters @{ movie_id = 99 }

Executes a parameterized non-query statement.
#>
function Invoke-OracleNonQuery {
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

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $connection = $null
    $command = $null
    $targetDataSource = $null

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
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleNonQuery started; DataSource={0}; CommandTimeout={1}" -f $targetDataSource, $CommandTimeout)
            if ($LogSql) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OracleNonQuery SQL: {0}" -f $Sql)
            }
            if ($LogParameters) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OracleNonQuery Parameters: {0}" -f ((Get-OracleParameterSummary -Parameters $Parameters) -join ', '))
            }
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText $Sql -CommandTimeout $CommandTimeout
        Add-OracleParameters -Command $command -Parameters $Parameters

        $rowsAffected = $command.ExecuteNonQuery()
        $sw.Stop()

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleNonQuery succeeded; DataSource={0}; RowsAffected={1}; ElapsedMs={2}" -f $connection.DataSource, $rowsAffected, $sw.ElapsedMilliseconds)
        }

        [pscustomobject]@{
            Success      = $true
            RowsAffected = $rowsAffected
            ElapsedMs    = $sw.ElapsedMilliseconds
        }
    }
    catch {
        $sw.Stop()
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Invoke-OracleNonQuery failed; DataSource={0}; ElapsedMs={1}; Error={2}" -f $targetDataSource, $sw.ElapsedMilliseconds, (Get-OracleExceptionMessage -Exception $_.Exception))
        }
        throw
    }
    finally {
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
