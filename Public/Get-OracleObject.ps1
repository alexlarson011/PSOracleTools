<#
.SYNOPSIS
Lists Oracle objects in a schema.

.DESCRIPTION
Queries ALL_OBJECTS and returns one stable result for each visible schema object. The current schema is used by
default. System-generated names, secondary objects created for domain indexes, and subobjects such as partitions
are omitted unless their corresponding include switches are supplied.

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
Optional schema to list. The current schema is used when this parameter is omitted.

.PARAMETER Name
Optional exact object name or names. Unquoted names are normalized to uppercase.

.PARAMETER NameLike
Optional Oracle LIKE pattern for object names, such as MOVIE%. Oracle LIKE matching is case-sensitive.

.PARAMETER ObjectType
Optional object type or types. Friendly values such as Table, PackageBody, DatabaseLink, and JavaSource are
supported. Native ALL_OBJECTS values such as PACKAGE BODY may also be supplied.

.PARAMETER Status
Optional status filter. Any is the default; Valid, Invalid, and NotApplicable map to Oracle status values.

.PARAMETER IncludeGenerated
Includes objects whose names Oracle marked as system-generated.

.PARAMETER IncludeSecondary
Includes secondary objects created by domain indexes.

.PARAMETER IncludeSubobjects
Includes rows with subobject names, such as table and index partitions.

.PARAMETER MaxObjects
Optional maximum number of result objects to return after Oracle ordering is applied.

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
Get-OracleObject -ProfileName 'ProdLow'

Lists user-named top-level objects in the current schema.

.EXAMPLE
Get-OracleObject -ProfileName 'ProdLow' -Schema 'HR' -ObjectType Table, View -NameLike 'EMP%'

Lists visible HR tables and views whose names begin with EMP.

.EXAMPLE
Get-OracleObject -ProfileName 'ProdLow' -ObjectType Package, PackageBody -Status Invalid

Lists invalid package specifications and bodies in the current schema.

.EXAMPLE
Get-OracleObject -ProfileName 'ProdLow' -IncludeGenerated -IncludeSecondary -IncludeSubobjects

Includes system-generated names, domain-index secondary objects, and partition subobjects.
#>
function Get-OracleObject {
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
        [Alias('ObjectName')]
        [string[]]$Name,

        [Parameter()]
        [string]$NameLike,

        [Parameter()]
        [string[]]$ObjectType,

        [Parameter()]
        [ValidateSet('Any', 'Valid', 'Invalid', 'NotApplicable')]
        [string]$Status = 'Any',

        [Parameter()]
        [switch]$IncludeGenerated,

        [Parameter()]
        [switch]$IncludeSecondary,

        [Parameter()]
        [switch]$IncludeSubobjects,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxObjects,

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

    if ($PSBoundParameters.ContainsKey('Name') -and $PSBoundParameters.ContainsKey('NameLike')) {
        throw '-Name and -NameLike cannot be used together.'
    }
    if ($PSBoundParameters.ContainsKey('Name') -and @($Name).Count -eq 0) {
        throw '-Name cannot be an empty collection.'
    }
    if ($PSBoundParameters.ContainsKey('NameLike') -and [string]::IsNullOrWhiteSpace($NameLike)) {
        throw '-NameLike cannot be empty.'
    }
    if ($PSBoundParameters.ContainsKey('ObjectType') -and @($ObjectType).Count -eq 0) {
        throw '-ObjectType cannot be an empty collection.'
    }

    $schemaIdentifier = if ($PSBoundParameters.ContainsKey('Schema')) {
        Resolve-OracleIdentifier -Name $Schema -Description 'Schema name'
    }
    else {
        $null
    }

    $parameters = @{
        schema_name = if ($null -eq $schemaIdentifier) { $null } else { $schemaIdentifier.Name }
    }
    $predicates = @("o.owner = coalesce(:schema_name, sys_context('USERENV', 'CURRENT_SCHEMA'))")

    if (-not $IncludeGenerated) {
        $predicates += "o.generated = 'N'"
    }
    if (-not $IncludeSecondary) {
        $predicates += "o.secondary = 'N'"
    }
    if (-not $IncludeSubobjects) {
        $predicates += 'o.subobject_name is null'
    }

    if ($PSBoundParameters.ContainsKey('Name')) {
        $normalizedNames = @(
            $Name |
                ForEach-Object { (Resolve-OracleIdentifier -Name $_ -Description 'Object name').Name } |
                Select-Object -Unique
        )
        $nameBinds = @()
        for ($i = 0; $i -lt $normalizedNames.Count; $i++) {
            $parameterName = 'object_name_{0}' -f $i
            $nameBinds += ':' + $parameterName
            $parameters[$parameterName] = $normalizedNames[$i]
        }
        $predicates += 'o.object_name in ({0})' -f ($nameBinds -join ', ')
    }
    elseif ($PSBoundParameters.ContainsKey('NameLike')) {
        $predicates += 'o.object_name like :name_like'
        $parameters.name_like = $NameLike
    }

    if ($PSBoundParameters.ContainsKey('ObjectType')) {
        $dictionaryTypes = @(
            $ObjectType |
                ForEach-Object { ConvertTo-OracleObjectTypeName -ObjectType $_ -Target Dictionary -AllowNative } |
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

    if ($Status -ne 'Any') {
        $predicates += 'o.status = :object_status'
        $parameters.object_status = switch ($Status) {
            'Valid' { 'VALID' }
            'Invalid' { 'INVALID' }
            'NotApplicable' { 'N/A' }
        }
    }

    $sql = @'
select o.owner as schema_name,
       o.object_name,
       o.subobject_name,
       o.object_id,
       o.data_object_id,
       o.object_type,
       o.created,
       o.last_ddl_time,
       o.timestamp as specification_timestamp,
       o.status,
       o.temporary,
       o.generated,
       o.secondary,
       o.namespace,
       o.edition_name
from all_objects o
'@
    $sql += "`nwhere $($predicates -join "`n  and ")`norder by o.object_type, o.object_name, o.subobject_name"

    $invocation = Get-OracleInvocationParameters -BoundParameters $PSBoundParameters -Target Query
    $invocation.Sql = $sql
    $invocation.Parameters = $parameters
    if ($PSBoundParameters.ContainsKey('MaxObjects')) {
        $invocation.MaxRows = $MaxObjects
    }

    foreach ($row in @(Invoke-OracleQuery @invocation)) {
        New-OracleResult -TypeName 'PSOracleTools.SchemaObjectResult' -Property ([ordered]@{
                Success                = $true
                Operation              = 'Get-OracleObject'
                ProfileName            = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
                Schema                 = [string]$row.schema_name
                Name                   = [string]$row.object_name
                SubobjectName          = $row.subobject_name
                ObjectType             = [string]$row.object_type
                Status                 = [string]$row.status
                ObjectId               = $row.object_id
                DataObjectId           = $row.data_object_id
                CreatedOn              = $row.created
                LastDdlTime            = $row.last_ddl_time
                SpecificationTimestamp = $row.specification_timestamp
                Temporary              = [string]$row.temporary -eq 'Y'
                Generated              = [string]$row.generated -eq 'Y'
                Secondary              = [string]$row.secondary -eq 'Y'
                Namespace              = $row.namespace
                EditionName            = $row.edition_name
            })
    }
}
