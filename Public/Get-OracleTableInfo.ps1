<#
.SYNOPSIS
Returns Oracle table, column, primary-key, and index metadata.

.DESCRIPTION
Reads ALL_TABLES, ALL_TAB_COLUMNS, ALL_CONSTRAINTS, ALL_CONS_COLUMNS, ALL_INDEXES, and ALL_IND_COLUMNS for one
or more visible tables. Each table produces one stable summary object with nested Columns, PrimaryKey, and Indexes
collections. The current schema is used unless -Schema is supplied.

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
Table name or names to inspect. Unquoted names are normalized to uppercase. Names can be supplied through the pipeline.

.PARAMETER Schema
Optional schema name. The current schema is used when this parameter is omitted.

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
Get-OracleTableInfo -ProfileName 'ProdLow' -Table 'movies'

Returns table metadata with nested column, primary-key, and index information.

.EXAMPLE
(Get-OracleTableInfo -ProfileName 'ProdLow' -Schema 'HR' -Table 'employees').Columns |
    Format-Table Position, Name, DataType, Nullable

Displays the column collection for HR.EMPLOYEES.

.EXAMPLE
'movies', 'actors' | Get-OracleTableInfo -ProfileName 'ProdLow'

Returns one table-information result for each piped table name.
#>
function Get-OracleTableInfo {
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
            $parameters = @{
                schema_name = if ($null -eq $schemaIdentifier) { $null } else { $schemaIdentifier.Name }
                table_name  = $tableIdentifier.Name
            }

            $tableSql = @'
select t.owner as schema_name,
       t.table_name,
       t.tablespace_name,
       t.temporary,
       t.partitioned,
       t.iot_type,
       t.compression,
       t.compress_for,
       t.num_rows,
       t.blocks,
       t.avg_row_len,
       t.last_analyzed
from all_tables t
where t.owner = coalesce(:schema_name, sys_context('USERENV', 'CURRENT_SCHEMA'))
  and t.table_name = :table_name
'@
            $invocation = @{} + $baseInvocation
            $invocation.Sql = $tableSql
            $invocation.Parameters = $parameters
            $tableRow = @(Invoke-OracleQuery @invocation | Select-Object -First 1)[0]
            if ($null -eq $tableRow) {
                $ownerName = if ($null -eq $schemaIdentifier) { 'the current schema' } else { "schema [$($schemaIdentifier.Name)]" }
                throw "Oracle table [$($tableIdentifier.Name)] was not found in $ownerName or is not visible to the connected user."
            }

            $columnSql = @'
select c.column_id,
       c.column_name,
       c.data_type,
       c.data_length,
       c.char_length,
       c.char_used,
       c.data_precision,
       c.data_scale,
       c.nullable,
       c.data_default,
       pk.constraint_name as primary_key_name,
       pk.position as primary_key_position
from all_tab_columns c
left join (
    select constraint_columns.owner,
           constraint_columns.table_name,
           constraint_columns.column_name,
           constraint_columns.constraint_name,
           constraint_columns.position
    from all_cons_columns constraint_columns
    join all_constraints constraints
      on constraints.owner = constraint_columns.owner
     and constraints.constraint_name = constraint_columns.constraint_name
     and constraints.table_name = constraint_columns.table_name
    where constraints.constraint_type = 'P'
) pk
  on pk.owner = c.owner
 and pk.table_name = c.table_name
 and pk.column_name = c.column_name
where c.owner = coalesce(:schema_name, sys_context('USERENV', 'CURRENT_SCHEMA'))
  and c.table_name = :table_name
order by c.column_id
'@
            $invocation = @{} + $baseInvocation
            $invocation.Sql = $columnSql
            $invocation.Parameters = $parameters
            $columnRows = @(Invoke-OracleQuery @invocation)
            $columns = @(
                foreach ($columnRow in $columnRows) {
                    New-OracleResult -TypeName 'PSOracleTools.TableColumnInfo' -Property ([ordered]@{
                            Position           = [int]$columnRow.column_id
                            Name               = [string]$columnRow.column_name
                            DataType           = [string]$columnRow.data_type
                            DataLength         = $columnRow.data_length
                            CharacterLength    = $columnRow.char_length
                            CharacterSemantics = [string]$columnRow.char_used
                            Precision          = $columnRow.data_precision
                            Scale              = $columnRow.data_scale
                            Nullable           = [string]$columnRow.nullable -eq 'Y'
                            Default            = $columnRow.data_default
                            PrimaryKeyPosition = if ($null -eq $columnRow.primary_key_position) { $null } else { [int]$columnRow.primary_key_position }
                        })
                }
            )

            $primaryKeyColumns = @($columns | Where-Object { $null -ne $_.PrimaryKeyPosition } | Sort-Object PrimaryKeyPosition)
            $primaryKey = if ($primaryKeyColumns.Count -eq 0) {
                $null
            }
            else {
                $primaryKeyName = [string](@($columnRows | Where-Object { $null -ne $_.primary_key_name } | Select-Object -First 1)[0].primary_key_name)
                New-OracleResult -TypeName 'PSOracleTools.PrimaryKeyInfo' -Property ([ordered]@{
                        Name    = $primaryKeyName
                        Columns = @($primaryKeyColumns.Name)
                    })
            }

            $indexSql = @'
select i.owner as index_owner,
       i.index_name,
       i.index_type,
       i.uniqueness,
       i.compression,
       i.prefix_length,
       i.tablespace_name,
       i.status,
       i.partitioned,
       i.last_analyzed,
       c.column_name,
       c.column_position,
       c.column_length,
       c.descend
from all_indexes i
left join all_ind_columns c
  on c.index_owner = i.owner
 and c.index_name = i.index_name
where i.table_owner = coalesce(:schema_name, sys_context('USERENV', 'CURRENT_SCHEMA'))
  and i.table_name = :table_name
order by i.index_name, c.column_position
'@
            $invocation = @{} + $baseInvocation
            $invocation.Sql = $indexSql
            $invocation.Parameters = $parameters
            $indexRows = @(Invoke-OracleQuery @invocation)
            $indexes = @(
                foreach ($indexGroup in @($indexRows | Group-Object -Property index_name)) {
                    $firstIndexRow = $indexGroup.Group[0]
                    $indexColumns = @(
                        foreach ($indexColumnRow in @($indexGroup.Group | Where-Object { $null -ne $_.column_name } | Sort-Object column_position)) {
                            New-OracleResult -TypeName 'PSOracleTools.IndexColumnInfo' -Property ([ordered]@{
                                    Position = [int]$indexColumnRow.column_position
                                    Name     = [string]$indexColumnRow.column_name
                                    Length   = $indexColumnRow.column_length
                                    Descending = [string]$indexColumnRow.descend -eq 'DESC'
                                })
                        }
                    )

                    New-OracleResult -TypeName 'PSOracleTools.TableIndexInfo' -Property ([ordered]@{
                            Schema             = [string]$firstIndexRow.index_owner
                            Name               = [string]$firstIndexRow.index_name
                            IndexType          = [string]$firstIndexRow.index_type
                            Unique             = [string]$firstIndexRow.uniqueness -eq 'UNIQUE'
                            CompressionEnabled = [string]$firstIndexRow.compression -eq 'ENABLED'
                            PrefixLength       = $firstIndexRow.prefix_length
                            Tablespace         = $firstIndexRow.tablespace_name
                            Status             = $firstIndexRow.status
                            Partitioned        = [string]$firstIndexRow.partitioned -eq 'YES'
                            LastAnalyzed       = $firstIndexRow.last_analyzed
                            Columns            = $indexColumns
                        })
                }
            )

            New-OracleResult -TypeName 'PSOracleTools.TableInfoResult' -Property ([ordered]@{
                    Success             = $true
                    Operation           = 'Get-OracleTableInfo'
                    ProfileName         = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
                    Schema              = [string]$tableRow.schema_name
                    Table               = [string]$tableRow.table_name
                    Tablespace          = $tableRow.tablespace_name
                    Temporary           = [string]$tableRow.temporary -eq 'Y'
                    Partitioned         = [string]$tableRow.partitioned -eq 'YES'
                    IndexOrganized      = -not [string]::IsNullOrWhiteSpace([string]$tableRow.iot_type)
                    IndexOrganization   = $tableRow.iot_type
                    CompressionEnabled  = [string]$tableRow.compression -eq 'ENABLED'
                    CompressionType     = $tableRow.compress_for
                    RowEstimate         = $tableRow.num_rows
                    Blocks              = $tableRow.blocks
                    AverageRowLength    = $tableRow.avg_row_len
                    LastAnalyzed        = $tableRow.last_analyzed
                    ColumnCount         = $columns.Count
                    Columns             = $columns
                    PrimaryKey          = $primaryKey
                    IndexCount          = $indexes.Count
                    Indexes             = $indexes
                })
        }
    }
}
