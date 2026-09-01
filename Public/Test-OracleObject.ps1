<#
.SYNOPSIS
Tests whether an Oracle schema object is visible to the connected user.

.DESCRIPTION
Queries ALL_OBJECTS for one or more object names and returns a stable result that distinguishes a successful
metadata lookup from whether a matching object exists. By default all object types are considered. The lookup
uses the current schema unless -Schema is supplied.

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

.PARAMETER Name
Object name or names to test. Unquoted names are normalized to uppercase. Names can be supplied through the pipeline.

.PARAMETER Schema
Optional schema name. The current schema is used when this parameter is omitted.

.PARAMETER ObjectType
Optional object type to require. The default, Any, reports all top-level matches for the name.

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
Test-OracleObject -ProfileName 'ProdLow' -Name 'movies' -ObjectType Table

Tests whether MOVIES is visible as a table in the current schema.

.EXAMPLE
'movie_pkg', 'missing_pkg' | Test-OracleObject -ProfileName 'ProdLow' -ObjectType Package

Returns one test result for each piped package name.

.EXAMPLE
if ((Test-OracleObject -ProfileName 'ProdLow' -Schema 'HR' -Name 'employees' -ObjectType Table).Exists) {
    'The table is visible.'
}

Uses the Exists property in a conditional check.
#>
function Test-OracleObject {
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
        [Alias('ObjectName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter()]
        [string]$Schema,

        [Parameter()]
        [ValidateSet('Any', 'Table', 'View', 'MaterializedView', 'Index', 'Sequence', 'Synonym', 'Procedure', 'Function', 'Package', 'PackageSpecification', 'PackageBody', 'Trigger', 'Type', 'TypeSpecification', 'TypeBody')]
        [string]$ObjectType = 'Any',

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

        $dictionaryType = if ($ObjectType -eq 'Any') {
            $null
        }
        else {
            ConvertTo-OracleObjectTypeName -ObjectType $ObjectType -Target Dictionary
        }

        $baseInvocation = Get-OracleInvocationParameters -BoundParameters $PSBoundParameters -Target Query
    }

    process {
        foreach ($objectName in $Name) {
            $objectIdentifier = Resolve-OracleIdentifier -Name $objectName -Description 'Object name'
            $typePredicate = if ($null -eq $dictionaryType) { '' } else { ' and o.object_type = :object_type' }
            $sql = @"
select requested.schema_name,
       o.owner,
       o.object_name,
       o.object_type,
       o.status,
       o.created,
       o.last_ddl_time
from (
    select coalesce(:schema_name, sys_context('USERENV', 'CURRENT_SCHEMA')) as schema_name,
           :object_name as object_name
    from dual
) requested
left join all_objects o
  on o.owner = requested.schema_name
 and o.object_name = requested.object_name
 and o.subobject_name is null$typePredicate
order by o.object_type
"@
            $parameters = @{
                schema_name = if ($null -eq $schemaIdentifier) { $null } else { $schemaIdentifier.Name }
                object_name = $objectIdentifier.Name
            }
            if ($null -ne $dictionaryType) {
                $parameters.object_type = $dictionaryType
            }

            $invocation = @{} + $baseInvocation
            $invocation.Sql = $sql
            $invocation.Parameters = $parameters
            $rows = @(Invoke-OracleQuery @invocation)
            if ($rows.Count -eq 0) {
                throw 'Oracle object lookup returned no rows.'
            }

            $matches = @(
                foreach ($row in $rows) {
                    if ($null -ne $row.object_name) {
                        New-OracleResult -TypeName 'PSOracleTools.ObjectMatch' -Property ([ordered]@{
                                Schema       = [string]$row.owner
                                Name         = [string]$row.object_name
                                ObjectType   = [string]$row.object_type
                                Status       = [string]$row.status
                                CreatedOn    = $row.created
                                LastDdlTime  = $row.last_ddl_time
                            })
                    }
                }
            )

            $exists = $matches.Count -gt 0
            New-OracleResult -TypeName 'PSOracleTools.ObjectTestResult' -Property ([ordered]@{
                    Success       = $true
                    Operation     = 'Test-OracleObject'
                    ProfileName   = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
                    Schema        = [string]$rows[0].schema_name
                    Name          = $objectIdentifier.Name
                    RequestedType = $ObjectType
                    Exists        = $exists
                    IsValid       = if ($exists) { @($matches.Status | Where-Object { $_ -ne 'VALID' }).Count -eq 0 } else { $null }
                    MatchCount    = $matches.Count
                    ObjectTypes   = @($matches | ForEach-Object { $_.ObjectType })
                    Statuses      = @($matches | ForEach-Object { $_.Status })
                    Matches       = $matches
                })
        }
    }
}
