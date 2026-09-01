<#
.SYNOPSIS
Returns an exact or estimated row count for an Oracle table.

.DESCRIPTION
Counts rows in one or more Oracle tables using the module's standard connection methods. Exact counts run
COUNT(*). Estimated counts read ALL_TABLES.NUM_ROWS and may be stale or unavailable when optimizer statistics
have not been gathered. Object identifiers are normalized and safely quoted before they are placed in SQL.

.PARAMETER ConnectionString
Full Oracle connection string.

.PARAMETER Credential
PSCredential used to build the Oracle connection string.

.PARAMETER DataSource
Oracle data source or TNS alias used with -Credential.

.PARAMETER CredentialName
Saved credential name used with -CredentialDataSource.

.PARAMETER CredentialDataSource
Oracle data source or TNS alias used with -CredentialName.

.PARAMETER ProfileName
Saved connection profile name.

.PARAMETER Table
Table name or names to count. Unquoted names are normalized to uppercase. Surround a case-sensitive name with
double quotes. Table names can also be supplied through the pipeline.

.PARAMETER Schema
Optional schema name. The current schema is used when this parameter is omitted.

.PARAMETER Estimate
Returns the optimizer statistics estimate from ALL_TABLES instead of running COUNT(*).

.PARAMETER Where
Optional SQL predicate for an exact count, without the WHERE keyword. Treat this as SQL text and use bind
parameters for values. This parameter cannot be used with -Estimate.

.PARAMETER Parameters
Optional bind parameters used by -Where. Supply a hashtable or OracleParameter objects.

.PARAMETER CommandTimeout
Command timeout in seconds. When omitted with -ProfileName, the profile default is used.

.PARAMETER CredentialStorePath
Optional custom path to the credential store JSON file.

.PARAMETER ProfileStorePath
Optional custom path to the profile store JSON file.

.PARAMETER Log
Writes operational log entries to the information stream.

.PARAMETER LogPath
Optional log file path.

.PARAMETER LogSql
Includes SQL text in log entries.

.PARAMETER LogParameters
Includes parameter names and types in log entries.

.EXAMPLE
Get-OracleRowCount -ProfileName 'ProdLow' -Table 'movies'

Returns an exact count for MOVIES in the current schema.

.EXAMPLE
Get-OracleRowCount -ProfileName 'ProdLow' -Table 'movies' -Estimate

Returns the last optimizer statistics estimate and its analysis date.

.EXAMPLE
Get-OracleRowCount -ProfileName 'ProdLow' -Table 'movies' -Where 'release_year >= :year' -Parameters @{ year = 2000 }

Returns an exact filtered count while binding the filter value.

.EXAMPLE
'movies', 'actors' | Get-OracleRowCount -ProfileName 'ProdLow'

Returns one stable row-count result for each piped table name.
#>
function Get-OracleRowCount {
    [CmdletBinding(DefaultParameterSetName = 'ByConnectionString', PositionalBinding = $false)]
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

        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('TableName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Table,

        [Parameter()]
        [string]$Schema,

        [Parameter()]
        [switch]$Estimate,

        [Parameter()]
        [Alias('Filter')]
        [string]$Where,

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

    begin {
        if ($Estimate -and ($PSBoundParameters.ContainsKey('Where') -or $PSBoundParameters.ContainsKey('Parameters'))) {
            throw '-Where and -Parameters cannot be used with -Estimate.'
        }

        if ($PSBoundParameters.ContainsKey('Parameters') -and -not $PSBoundParameters.ContainsKey('Where')) {
            throw '-Parameters requires -Where.'
        }

        if ($PSBoundParameters.ContainsKey('Where') -and [string]::IsNullOrWhiteSpace($Where)) {
            throw '-Where cannot be empty.'
        }

        $schemaIdentifier = if ($PSBoundParameters.ContainsKey('Schema')) {
            Resolve-OracleIdentifier -Name $Schema -Description 'Schema name'
        }
        else {
            $null
        }

        $baseInvocation = Get-OracleInvocationParameters -BoundParameters $PSBoundParameters -Target Query
    }

    process {
        foreach ($tableName in $Table) {
            $tableIdentifier = Resolve-OracleIdentifier -Name $tableName -Description 'Table name'
            $startedOn = Get-Date
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            if ($Estimate) {
                $sql = @'
select requested.schema_name,
       t.table_name,
       t.num_rows,
       t.last_analyzed
from (
    select coalesce(:schema_name, sys_context('USERENV', 'CURRENT_SCHEMA')) as schema_name,
           :table_name as table_name
    from dual
) requested
left join all_tables t
  on t.owner = requested.schema_name
 and t.table_name = requested.table_name
'@
                $invocation = @{} + $baseInvocation
                $invocation.Sql = $sql
                $invocation.Parameters = @{
                    schema_name = if ($null -eq $schemaIdentifier) { $null } else { $schemaIdentifier.Name }
                    table_name  = $tableIdentifier.Name
                }

                $row = @(Invoke-OracleQuery @invocation | Select-Object -First 1)[0]
                if ($null -eq $row -or $null -eq $row.table_name) {
                    $ownerName = if ($null -eq $schemaIdentifier) { 'the current schema' } else { "schema [$($schemaIdentifier.Name)]" }
                    throw "Oracle table [$($tableIdentifier.Name)] was not found in $ownerName or is not visible to the connected user."
                }

                $schemaName = [string]$row.schema_name
                $rowCount = if ($null -eq $row.num_rows) { $null } else { [decimal]$row.num_rows }
                $lastAnalyzed = $row.last_analyzed
                $countType = 'Estimated'
            }
            else {
                $qualifiedTable = if ($null -eq $schemaIdentifier) {
                    $tableIdentifier.Sql
                }
                else {
                    '{0}.{1}' -f $schemaIdentifier.Sql, $tableIdentifier.Sql
                }

                $whereClause = if ($PSBoundParameters.ContainsKey('Where')) { "`nwhere $($Where.Trim())" } else { '' }
                $sql = @"
select sys_context('USERENV', 'CURRENT_SCHEMA') as schema_name,
       (select count(*) from $qualifiedTable$whereClause) as row_count
from dual
"@
                $invocation = @{} + $baseInvocation
                $invocation.Sql = $sql
                if ($PSBoundParameters.ContainsKey('Parameters')) {
                    $invocation.Parameters = $Parameters
                }

                $row = @(Invoke-OracleQuery @invocation | Select-Object -First 1)[0]
                if ($null -eq $row) {
                    throw 'Oracle row-count query returned no rows.'
                }

                $schemaName = if ($null -eq $schemaIdentifier) { [string]$row.schema_name } else { $schemaIdentifier.Name }
                $rowCount = [decimal]$row.row_count
                $lastAnalyzed = $null
                $countType = 'Exact'
            }

            $stopwatch.Stop()
            New-OracleResult -TypeName 'PSOracleTools.RowCountResult' -Property ([ordered]@{
                    Success             = $true
                    Operation           = 'Get-OracleRowCount'
                    ProfileName         = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
                    Schema              = $schemaName
                    Table               = $tableIdentifier.Name
                    RowCount            = $rowCount
                    CountType           = $countType
                    StatisticsAvailable = if ($Estimate) { $null -ne $rowCount } else { $null }
                    LastAnalyzed        = $lastAnalyzed
                    StartedOn           = $startedOn
                    CompletedOn         = Get-Date
                    ElapsedMs           = $stopwatch.ElapsedMilliseconds
                })
        }
    }
}
