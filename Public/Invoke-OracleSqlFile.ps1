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

.EXAMPLE
Invoke-OracleSqlFile -ProfileName 'ProdLow' -Path '.\scripts\refresh_movies.sql'

Executes all supported statements from a SQL file using a saved connection profile.

.EXAMPLE
Invoke-OracleSqlFile -ConnectionString $cs -Path '.\scripts\deploy_movies.sql' -Log -LogPath '.\logs\oracle.log'

Executes a SQL file with logging enabled.
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

    $statements = @(Split-OracleScriptStatements -Text $sqlText)
    if ($statements.Count -eq 0) {
        throw "SQL file did not contain any executable statements: $Path"
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $connection = $null
    $command = $null
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
                $cs = New-OracleConnectionString -DataSource $targetDataSource -UserId $resolvedCredential.UserName -Password ($resolvedCredential.GetNetworkCredential().Password)
            }
        }

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile started; Path={0}; DataSource={1}; StatementCount={2}; CommandTimeout={3}" -f $Path, $targetDataSource, $statements.Count, $CommandTimeout)
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

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
                $rowsAffected = $command.ExecuteNonQuery()
                $statementSw.Stop()

                if ($Log -or $LogPath) {
                    Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile statement succeeded; Path={0}; DataSource={1}; StatementIndex={2}; Kind={3}; RowsAffected={4}; ElapsedMs={5}" -f $Path, $connection.DataSource, $statement.Index, $statement.Kind, $rowsAffected, $statementSw.ElapsedMilliseconds)
                }

                $statementResults.Add([pscustomobject]@{
                        Index        = $statement.Index
                        Kind         = $statement.Kind
                        RowsAffected = $rowsAffected
                        ElapsedMs    = $statementSw.ElapsedMilliseconds
                    }) | Out-Null
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

        $sw.Stop()

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleSqlFile succeeded; Path={0}; DataSource={1}; StatementCount={2}; ElapsedMs={3}" -f $Path, $connection.DataSource, $statementResults.Count, $sw.ElapsedMilliseconds)
        }

        return [pscustomobject]@{
            Success        = $true
            Path           = $Path
            StatementCount = $statementResults.Count
            ElapsedMs      = $sw.ElapsedMilliseconds
            Statements     = $statementResults.ToArray()
        }
    }
    catch {
        $sw.Stop()
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Invoke-OracleSqlFile failed; Path={0}; DataSource={1}; ElapsedMs={2}; Error={3}" -f $Path, $targetDataSource, $sw.ElapsedMilliseconds, (Get-OracleExceptionMessage -Exception $_.Exception))
        }
        throw
    }
    finally {
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
