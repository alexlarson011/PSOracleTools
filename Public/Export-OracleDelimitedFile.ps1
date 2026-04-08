<#
.SYNOPSIS
Exports query results to a delimited text file.

.DESCRIPTION
Runs a query and writes the resulting rows to a delimited UTF-8 file.
Supports raw connection strings, PSCredential input, or saved credential names.

.PARAMETER Sql
SQL query text to export.

.PARAMETER Path
Output file path.

.PARAMETER Delimiter
Delimiter used between exported values.

.PARAMETER IncludeHeader
Includes a header row with column names.

.PARAMETER NullValue
Replacement text for null values.

.PARAMETER QuoteAll
Quotes every field in the output.

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
Export-OracleDelimitedFile -ProfileName 'ProdLow' -Sql 'select movie_id, movie_nm from ps_tools.movies' -Path '.\output\movies.txt' -IncludeHeader

Exports query results to a delimited file using a saved connection profile.
#>
function Export-OracleDelimitedFile {
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
        [string]$Delimiter = '|',

        [Parameter()]
        [switch]$IncludeHeader,

        [Parameter()]
        [string]$NullValue = '',

        [Parameter()]
        [switch]$QuoteAll,

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
    $writer = $null
    $rowCount = 0
    $targetDataSource = $null
    $resolvedProfile = $null

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

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Export-OracleDelimitedFile started; DataSource={0}; OutputPath={1}; CommandTimeout={2}" -f $targetDataSource, $Path, $CommandTimeout)
            if ($LogSql) {
                Write-OracleLog -Path $LogPath -Message ("Export-OracleDelimitedFile SQL: {0}" -f $Sql)
            }
            if ($LogParameters) {
                Write-OracleLog -Path $LogPath -Message ("Export-OracleDelimitedFile Parameters: {0}" -f ((Get-OracleParameterSummary -Parameters $Parameters) -join ', '))
            }
        }

        $directory = Split-Path -Path $Path -Parent
        if ($directory -and -not (Test-Path -Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText $Sql -CommandTimeout $CommandTimeout
        Add-OracleParameters -Command $command -Parameters $Parameters

        $reader = $command.ExecuteReader()
        $writer = New-Object System.IO.StreamWriter($Path, $false, [System.Text.Encoding]::UTF8)

        if ($IncludeHeader) {
            $header = for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                ConvertTo-DelimitedValue -Value $reader.GetName($i) -Delimiter $Delimiter -NullValue $NullValue -QuoteAll:$QuoteAll
            }
            $writer.WriteLine(($header -join $Delimiter))
        }

        while ($reader.Read()) {
            $line = for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $value = if ($reader.IsDBNull($i)) { $null } else { $reader.GetValue($i) }
                ConvertTo-DelimitedValue -Value $value -Delimiter $Delimiter -NullValue $NullValue -QuoteAll:$QuoteAll
            }

            $writer.WriteLine(($line -join $Delimiter))
            $rowCount++
        }

        $sw.Stop()

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Export-OracleDelimitedFile succeeded; DataSource={0}; OutputPath={1}; RowCount={2}; ElapsedMs={3}" -f $connection.DataSource, $Path, $rowCount, $sw.ElapsedMilliseconds)
        }

        [pscustomobject]@{
            Success   = $true
            Path      = $Path
            RowCount  = $rowCount
            ElapsedMs = $sw.ElapsedMilliseconds
        }
    }
    catch {
        $sw.Stop()
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Export-OracleDelimitedFile failed; DataSource={0}; OutputPath={1}; ElapsedMs={2}; Error={3}" -f $targetDataSource, $Path, $sw.ElapsedMilliseconds, (Get-OracleExceptionMessage -Exception $_.Exception))
        }
        throw
    }
    finally {
        if ($writer) { $writer.Flush() }
        Close-OracleResource -Object $writer
        Close-OracleResource -Object $reader
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
