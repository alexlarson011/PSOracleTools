<#
.SYNOPSIS
Returns creation DDL for an Oracle schema object.

.DESCRIPTION
Calls DBMS_METADATA.GET_DDL for one or more named schema objects and returns a stable object containing the DDL.
Unquoted identifiers are normalized to uppercase; quoted identifiers preserve case. Oracle applies its default DDL
transform settings. Retrieving objects in another schema may require additional catalog privileges.

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
Object name or names whose DDL should be returned. Names can be supplied through the pipeline.

.PARAMETER ObjectType
Friendly Oracle object type. Table is the default. Package and Type can return both specification and body; use
PackageSpecification, PackageBody, TypeSpecification, or TypeBody when only one part is wanted.

.PARAMETER Schema
Optional schema name. The current schema is used when this parameter is omitted.

.PARAMETER DdlOnly
Returns only the DDL string instead of the stable result object.

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
Get-OracleObjectDdl -ProfileName 'ProdLow' -Name 'movies' -ObjectType Table

Returns a stable result whose Ddl property contains the table creation statement.

.EXAMPLE
Get-OracleObjectDdl -ProfileName 'ProdLow' -Name 'movie_pkg' -ObjectType PackageBody -DdlOnly

Returns only the package body DDL string.

.EXAMPLE
'movies', 'actors' | Get-OracleObjectDdl -ProfileName 'ProdLow' -ObjectType Table

Returns one DDL result for each piped table name.
#>
function Get-OracleObjectDdl {
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

        [Parameter(Position = 1)]
        [ValidateSet('Table', 'View', 'MaterializedView', 'Index', 'Sequence', 'Synonym', 'Procedure', 'Function', 'Package', 'PackageSpecification', 'PackageBody', 'Trigger', 'Type', 'TypeSpecification', 'TypeBody')]
        [string]$ObjectType = 'Table',

        [Parameter()]
        [string]$Schema,

        [Parameter()]
        [switch]$DdlOnly,

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

        $metadataType = ConvertTo-OracleObjectTypeName -ObjectType $ObjectType -Target Metadata
        $baseInvocation = Get-OracleInvocationParameters -BoundParameters $PSBoundParameters -Target Query
    }

    process {
        foreach ($objectName in $Name) {
            $objectIdentifier = Resolve-OracleIdentifier -Name $objectName -Description 'Object name'
            $sql = @'
select coalesce(:schema_name, sys_context('USERENV', 'CURRENT_SCHEMA')) as schema_name,
       dbms_metadata.get_ddl(
           :metadata_type,
           :object_name,
           coalesce(:schema_name, sys_context('USERENV', 'CURRENT_SCHEMA'))
       ) as ddl
from dual
'@
            $invocation = @{} + $baseInvocation
            $invocation.Sql = $sql
            $invocation.Parameters = @{
                metadata_type = $metadataType
                object_name   = $objectIdentifier.Name
                schema_name   = if ($null -eq $schemaIdentifier) { $null } else { $schemaIdentifier.Name }
            }

            $row = @(Invoke-OracleQuery @invocation | Select-Object -First 1)[0]
            if ($null -eq $row -or $null -eq $row.ddl) {
                throw "Oracle returned no DDL for [$ObjectType] object [$($objectIdentifier.Name)]."
            }

            $ddl = ([string]$row.ddl).Trim()
            if ($DdlOnly) {
                $ddl
                continue
            }

            New-OracleResult -TypeName 'PSOracleTools.ObjectDdlResult' -Property ([ordered]@{
                    Success      = $true
                    Operation    = 'Get-OracleObjectDdl'
                    ProfileName  = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
                    Schema       = [string]$row.schema_name
                    Name         = $objectIdentifier.Name
                    ObjectType   = $ObjectType
                    MetadataType = $metadataType
                    Length       = $ddl.Length
                    Ddl          = $ddl
                })
        }
    }
}
