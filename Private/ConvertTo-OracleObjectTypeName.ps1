function ConvertTo-OracleObjectTypeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ObjectType,

        [Parameter(Mandatory)]
        [ValidateSet('Dictionary', 'Metadata')]
        [string]$Target,

        [Parameter()]
        [switch]$AllowNative
    )

    $dictionaryTypes = @{
        Table                = 'TABLE'
        View                 = 'VIEW'
        MaterializedView     = 'MATERIALIZED VIEW'
        Index                = 'INDEX'
        Sequence             = 'SEQUENCE'
        Synonym              = 'SYNONYM'
        Procedure            = 'PROCEDURE'
        Function             = 'FUNCTION'
        Package              = 'PACKAGE'
        PackageSpecification = 'PACKAGE'
        PackageBody          = 'PACKAGE BODY'
        Trigger              = 'TRIGGER'
        Type                 = 'TYPE'
        TypeSpecification    = 'TYPE'
        TypeBody             = 'TYPE BODY'
        Cluster              = 'CLUSTER'
        DatabaseLink         = 'DATABASE LINK'
        Dimension            = 'DIMENSION'
        Directory            = 'DIRECTORY'
        IndexType            = 'INDEXTYPE'
        JavaClass            = 'JAVA CLASS'
        JavaResource         = 'JAVA RESOURCE'
        JavaSource           = 'JAVA SOURCE'
        Job                  = 'JOB'
        Library              = 'LIBRARY'
        Lob                  = 'LOB'
        MaterializedViewLog  = 'MATERIALIZED VIEW LOG'
        Operator             = 'OPERATOR'
        Queue                = 'QUEUE'
        Rule                 = 'RULE'
        RuleSet              = 'RULE SET'
        XmlSchema            = 'XML SCHEMA'
    }

    $metadataTypes = @{
        Table                = 'TABLE'
        View                 = 'VIEW'
        MaterializedView     = 'MATERIALIZED_VIEW'
        Index                = 'INDEX'
        Sequence             = 'SEQUENCE'
        Synonym              = 'SYNONYM'
        Procedure            = 'PROCEDURE'
        Function             = 'FUNCTION'
        Package              = 'PACKAGE'
        PackageSpecification = 'PACKAGE_SPEC'
        PackageBody          = 'PACKAGE_BODY'
        Trigger              = 'TRIGGER'
        Type                 = 'TYPE'
        TypeSpecification    = 'TYPE_SPEC'
        TypeBody             = 'TYPE_BODY'
    }

    $types = if ($Target -eq 'Dictionary') { $dictionaryTypes } else { $metadataTypes }
    if (-not $types.ContainsKey($ObjectType)) {
        if ($Target -eq 'Dictionary' -and $AllowNative) {
            $nativeType = $ObjectType.Trim()
            if ([string]::IsNullOrWhiteSpace($nativeType) -or $nativeType.IndexOfAny([char[]]@("`0", "`r", "`n")) -ge 0) {
                throw 'Oracle dictionary object type cannot be empty or contain control characters.'
            }

            return $nativeType.Replace('_', ' ').ToUpperInvariant()
        }

        throw "Oracle object type [$ObjectType] is not supported for [$Target] operations."
    }

    return $types[$ObjectType]
}
