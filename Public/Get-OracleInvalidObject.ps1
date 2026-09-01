<#
.SYNOPSIS
Returns invalid Oracle schema objects visible to the connected user.

.DESCRIPTION
Queries ALL_OBJECTS for INVALID top-level objects. The current schema is searched by default. Use -Schema for a
specific visible schema or -AllSchemas for every schema represented in ALL_OBJECTS. Optional object-type filters
are translated to Oracle dictionary type names and bound safely.

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

.PARAMETER Schema
Optional schema to search. The current schema is used when this parameter is omitted.

.PARAMETER AllSchemas
Searches every schema visible through ALL_OBJECTS. This parameter cannot be combined with -Schema.

.PARAMETER ObjectType
Optional one or more friendly object types to include.

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
Get-OracleInvalidObject -ProfileName 'ProdLow'

Lists invalid objects in the current schema.

.EXAMPLE
Get-OracleInvalidObject -ProfileName 'ProdLow' -ObjectType Package, PackageBody, Procedure, Function

Lists invalid stored program units in the current schema.

.EXAMPLE
Get-OracleInvalidObject -ProfileName 'ProdLow' -Schema 'HR'

Lists invalid objects in the visible HR schema.
#>
function Get-OracleInvalidObject {
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

        [Parameter()]
        [string]$Schema,

        [Parameter()]
        [switch]$AllSchemas,

        [Parameter()]
        [ValidateSet('Table', 'View', 'MaterializedView', 'Index', 'Sequence', 'Synonym', 'Procedure', 'Function', 'Package', 'PackageSpecification', 'PackageBody', 'Trigger', 'Type', 'TypeSpecification', 'TypeBody')]
        [string[]]$ObjectType,

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

    if ($AllSchemas -and $PSBoundParameters.ContainsKey('Schema')) {
        throw '-Schema and -AllSchemas cannot be used together.'
    }

    $schemaIdentifier = if ($PSBoundParameters.ContainsKey('Schema')) {
        Resolve-OracleIdentifier -Name $Schema -Description 'Schema name'
    }
    else {
        $null
    }

    $parameters = @{}
    $predicates = @("o.status = 'INVALID'", 'o.subobject_name is null')
    if (-not $AllSchemas) {
        $predicates += "o.owner = coalesce(:schema_name, sys_context('USERENV', 'CURRENT_SCHEMA'))"
        $parameters.schema_name = if ($null -eq $schemaIdentifier) { $null } else { $schemaIdentifier.Name }
    }

    if ($PSBoundParameters.ContainsKey('ObjectType')) {
        $dictionaryTypes = @(
            $ObjectType |
                ForEach-Object { ConvertTo-OracleObjectTypeName -ObjectType $_ -Target Dictionary } |
                Select-Object -Unique
        )
        $typeBinds = @()
        for ($i = 0; $i -lt $dictionaryTypes.Count; $i++) {
            $parameterName = 'object_type_{0}' -f $i
            $typeBinds += ':' + $parameterName
            $parameters[$parameterName] = $dictionaryTypes[$i]
        }
        $predicates += 'o.object_type in ({0})' -f ($typeBinds -join ', ')
    }

    $sql = @'
select o.owner as schema_name,
       o.object_name,
       o.object_type,
       o.status,
       o.created,
       o.last_ddl_time,
       (select count(*)
          from all_errors e
         where e.owner = o.owner
           and e.name = o.object_name
           and e.type = o.object_type) as error_count
from all_objects o
'@
    $sql += "`nwhere $($predicates -join "`n  and ")`norder by o.owner, o.object_type, o.object_name"

    $invocation = Get-OracleInvocationParameters -BoundParameters $PSBoundParameters -Target Query
    $invocation.Sql = $sql
    if ($parameters.Count -gt 0) {
        $invocation.Parameters = $parameters
    }

    foreach ($row in @(Invoke-OracleQuery @invocation)) {
        New-OracleResult -TypeName 'PSOracleTools.InvalidObjectResult' -Property ([ordered]@{
                Success      = $true
                Operation    = 'Get-OracleInvalidObject'
                ProfileName  = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
                Schema       = [string]$row.schema_name
                Name         = [string]$row.object_name
                ObjectType   = [string]$row.object_type
                Status       = [string]$row.status
                ErrorCount   = [int]$row.error_count
                CreatedOn    = $row.created
                LastDdlTime  = $row.last_ddl_time
            })
    }
}
