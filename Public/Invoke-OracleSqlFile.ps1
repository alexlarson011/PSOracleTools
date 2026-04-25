<#
.SYNOPSIS
Executes SQL or PL/SQL from a file.

.DESCRIPTION
Reads a .sql file from disk, parses executable statements, and runs them in order on a single Oracle connection.
Supports semicolon-terminated SQL statements and PL/SQL-style blocks terminated by a slash on its own line.
This command does not emulate SQL*Plus directives such as SET, SPOOL, PROMPT, or @child.sql.
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

.PARAMETER UseTransaction
Executes all statements in one Oracle transaction. Commits only after every statement succeeds and rolls back on failure.

.PARAMETER AllowDdlInTransaction
Allows obvious DDL or DCL statements when -UseTransaction is supplied. Oracle may implicitly commit DDL, so rollback safety is not guaranteed for those scripts.

.EXAMPLE
Invoke-OracleSqlFile -ProfileName 'ProdLow' -Path '.\scripts\refresh_movies.sql'

Executes all supported statements from a SQL file using a saved connection profile.

.EXAMPLE
Invoke-OracleSqlFile -ConnectionString $cs -Path '.\scripts\deploy_movies.sql' -Log -LogPath '.\logs\oracle.log'

Executes a SQL file with logging enabled.

.EXAMPLE
Invoke-OracleSqlFile -ProfileName 'ProdLow' -Path '.\scripts\load_movies.sql' -UseTransaction

Executes a SQL file in one transaction and rolls back all statements if any statement fails.
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
        [switch]$LogSql,

        [Parameter()]
        [switch]$UseTransaction,

        [Parameter()]
        [switch]$AllowDdlInTransaction
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "SQL file not found: $Path"
    }

    $sqlText = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($sqlText)) {
        throw "SQL file is empty: $Path"
    }

    $statements = @(Split-OracleScriptStatements -Text $sqlText)
    if ($statements.Count -eq 0) {
        throw "SQL file did not contain any executable statements: $Path"
    }

    if ($UseTransaction -and -not $AllowDdlInTransaction) {
        $ddlStatements = @($statements | Where-Object { Test-OracleDdlStatement -StatementText $_.Text })
        if ($ddlStatements.Count -gt 0) {
            throw ("-UseTransaction cannot be used with DDL/DCL statement(s) without -AllowDdlInTransaction. Oracle can implicitly commit DDL. Statement index(es): {0}" -f (($ddlStatements | Select-Object -ExpandProperty Index) -join ', '))
        }
    }

    $startedOn = Get-Date
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $connection = $null
    $command = $null
    $transaction = $null
    $transactionCommitted = $false
    $transactionRolledBack = $false
    $targetDataSource = $null
    $resolvedProfile = $null
    $statementResults = New-Object System.Collections.Generic.List[object]

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

                $resolvedCredential = Resolve-OracleCredential -CredentialName ([string]$resolvedProfile.CredentialName) -CredentialStorePath $CredentialStorePath
                $targetDataSource = [string]$resolvedProfile.DataSource
                $connectionStringParameters = @{
                    DataSource = $targetDataSource
                    UserId     = $resolvedCredential.UserName
                    Password   = $resolvedCredential.GetNetworkCredential().Password
                }
                if ($resolvedProfile.ConnectionTimeout) {
                    $connectionStringParameters.ConnectionTimeout = [int]$resolvedProfile.ConnectionTimeout
                }
                $cs = New-OracleConnectionString @connectionStringParameters
            }
        }

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile started; Path={0}; DataSource={1}; StatementCount={2}; CommandTimeout={3}; UseTransaction={4}" -f $Path, $targetDataSource, $statements.Count, $CommandTimeout, [bool]$UseTransaction)
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        if ($UseTransaction) {
            $transaction = $connection.BeginTransaction()
            if ($Log -or $LogPath) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile transaction started; Path={0}; DataSource={1}" -f $Path, $connection.DataSource)
            }
        }

        foreach ($statement in $statements) {
            $statementSw = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                if ($Log -or $LogPath) {
                    Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile statement started; Path={0}; DataSource={1}; StatementIndex={2}; Kind={3}" -f $Path, $connection.DataSource, $statement.Index, $statement.Kind)
                    if ($LogSql) {
                        Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile statement text [{0}]: {1}" -f $statement.Index, (ConvertTo-OracleLogText -Text $statement.Text))
                    }
                }

                $command = New-OracleCommand -Connection $connection -CommandText $statement.Text -CommandTimeout $CommandTimeout
                if ($transaction) {
                    $command.Transaction = $transaction
                }
                $rowsAffected = $command.ExecuteNonQuery()
                $statementSw.Stop()

                if ($Log -or $LogPath) {
                    Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile statement succeeded; Path={0}; DataSource={1}; StatementIndex={2}; Kind={3}; RowsAffected={4}; ElapsedMs={5}" -f $Path, $connection.DataSource, $statement.Index, $statement.Kind, $rowsAffected, $statementSw.ElapsedMilliseconds)
                }

                $statementResults.Add((New-OracleResult -TypeName 'PSOracleTools.SqlFileStatementResult' -Property ([ordered]@{
                        Index        = $statement.Index
                        Kind         = $statement.Kind
                        IsDdl        = Test-OracleDdlStatement -StatementText $statement.Text
                        Succeeded    = $true
                        RowsAffected = $rowsAffected
                        ElapsedMs    = $statementSw.ElapsedMilliseconds
                    }))) | Out-Null
            }
            catch {
                $statementSw.Stop()
                if ($Log -or $LogPath) {
                    Write-OracleLog -Path $LogPath -Level ERROR -Message ("Invoke-OracleSqlFile statement failed; Path={0}; DataSource={1}; StatementIndex={2}; Kind={3}; ElapsedMs={4}; Error={5}" -f $Path, $targetDataSource, $statement.Index, $statement.Kind, $statementSw.ElapsedMilliseconds, (Get-OracleExceptionMessage -Exception $_.Exception))
                }

                throw "Failed executing statement $($statement.Index) from $Path. $(Get-OracleExceptionMessage -Exception $_.Exception)"
            }
            finally {
                Close-OracleResource -Object $command
                $command = $null
            }
        }

        if ($transaction) {
            $transaction.Commit()
            $transactionCommitted = $true
            if ($Log -or $LogPath) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile transaction committed; Path={0}; DataSource={1}" -f $Path, $connection.DataSource)
            }
        }

        $sw.Stop()

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile succeeded; Path={0}; DataSource={1}; StatementCount={2}; ElapsedMs={3}" -f $Path, $connection.DataSource, $statementResults.Count, $sw.ElapsedMilliseconds)
        }

        return New-OracleResult -TypeName 'PSOracleTools.SqlFileResult' -Property ([ordered]@{
                Success         = $true
                Operation       = 'Invoke-OracleSqlFile'
                DataSource      = $connection.DataSource
                ProfileName     = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
                Path            = $Path
                StartedOn       = $startedOn
                CompletedOn     = Get-Date
                ElapsedMs       = $sw.ElapsedMilliseconds
                StatementCount  = $statementResults.Count
                TransactionUsed = [bool]$UseTransaction
                Committed       = $transactionCommitted
                RolledBack      = $transactionRolledBack
                Statements      = $statementResults.ToArray()
            })
    }
    catch {
        $sw.Stop()
        if ($transaction -and -not $transactionCommitted -and -not $transactionRolledBack) {
            try {
                $transaction.Rollback()
                $transactionRolledBack = $true
                if ($Log -or $LogPath) {
                    Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile transaction rolled back; Path={0}; DataSource={1}" -f $Path, $targetDataSource)
                }
            }
            catch {
                if ($Log -or $LogPath) {
                    Write-OracleLog -Path $LogPath -Level ERROR -Message ("Invoke-OracleSqlFile transaction rollback failed; Path={0}; DataSource={1}; Error={2}" -f $Path, $targetDataSource, (Get-OracleExceptionMessage -Exception $_.Exception))
                }
            }
        }

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Invoke-OracleSqlFile failed; Path={0}; DataSource={1}; ElapsedMs={2}; Error={3}" -f $Path, $targetDataSource, $sw.ElapsedMilliseconds, (Get-OracleExceptionMessage -Exception $_.Exception))
        }
        throw
    }
    finally {
        Close-OracleResource -Object $command
        Close-OracleResource -Object $transaction
        Close-OracleResource -Object $connection
    }
}
