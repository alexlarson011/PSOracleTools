<#
.SYNOPSIS
Runs a read-only smoke test against an Oracle connection profile.

.DESCRIPTION
Imports the local PSOracleTools module and verifies connection, bounded connection waiting, Oracle server identity,
scalar queries, bounded queries, invalid-object inspection, and CSV export. When -MetadataTable is supplied, it also
tests row counts, schema inventory, object visibility, table metadata, and DDL retrieval for that table. It does not issue DDL, DML,
PL/SQL, or stored-procedure calls.

.PARAMETER ProfileName
Saved PSOracleTools connection profile to test.

.PARAMETER OutputDirectory
Directory where the temporary smoke-test CSV file will be written. Defaults to a unique temporary directory.

.PARAMETER MetadataTable
Optional table owned by the connected user for row-count, schema-inventory, object, table-information, and DDL retrieval checks.

.PARAMETER MetadataSchema
Optional schema for -MetadataTable. The current schema is used when this parameter is omitted.

.EXAMPLE
.\scripts\Test-LiveOracle.ps1 -ProfileName 'ProdLow' -MetadataTable 'movies'

Runs the read-only smoke test and metadata checks using the ProdLow connection profile.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProfileName,

    [Parameter()]
    [string]$OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) ('PSOracleTools-LiveTest-' + [guid]::NewGuid().ToString('N'))),

    [Parameter()]
    [string]$MetadataTable,

    [Parameter()]
    [string]$MetadataSchema
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path -Path $repoRoot -ChildPath 'PSOracleTools.psd1'

Import-Module $manifestPath -Force
New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null

Write-Host "Testing connection profile [$ProfileName]..."
$connection = Test-OracleConnection -ProfileName $ProfileName
if (-not $connection.Success) {
    throw "Connection test did not succeed for profile [$ProfileName]."
}

$wait = Wait-OracleConnection -ProfileName $ProfileName -TimeoutSeconds 10 -RetryIntervalSeconds 1
if (-not $wait.Success) {
    throw "Connection wait did not succeed for profile [$ProfileName]."
}

$server = Get-OracleServerInfo -ProfileName $ProfileName
$scalar = Invoke-OracleScalar -ProfileName $ProfileName -Sql 'select sysdate from dual'
$invalidObjects = @(Get-OracleInvalidObject -ProfileName $ProfileName)
$rows = @(Invoke-OracleQuery -ProfileName $ProfileName -Sql 'select level as row_number from dual connect by level <= 3' -MaxRows 2)
if ($rows.Count -ne 2) {
    throw "Expected -MaxRows 2 to return two rows, but received [$($rows.Count)]."
}

$csvPath = Join-Path $OutputDirectory 'oracle-smoke-test.csv'
$export = Export-OracleCsv -ProfileName $ProfileName -Sql 'select level as row_number from dual connect by level <= 3' -Path $csvPath -NoClobber
if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
    throw "CSV export was not created at [$csvPath]."
}

$metadataResult = $null
if ($PSBoundParameters.ContainsKey('MetadataTable')) {
    $metadataParameters = @{ ProfileName = $ProfileName; Table = $MetadataTable }
    $objectParameters = @{ ProfileName = $ProfileName; Name = $MetadataTable; ObjectType = 'Table' }
    $ddlParameters = @{ ProfileName = $ProfileName; Name = $MetadataTable; ObjectType = 'Table' }
    if ($PSBoundParameters.ContainsKey('MetadataSchema')) {
        $metadataParameters.Schema = $MetadataSchema
        $objectParameters.Schema = $MetadataSchema
        $ddlParameters.Schema = $MetadataSchema
    }

    $rowCount = Get-OracleRowCount @metadataParameters
    $listedObjects = @(Get-OracleObject @objectParameters)
    if ($listedObjects.Count -ne 1) {
        throw "Expected one schema inventory row for metadata table [$MetadataTable], but received [$($listedObjects.Count)]."
    }
    $objectTest = Test-OracleObject @objectParameters
    if (-not $objectTest.Exists) {
        throw "Metadata table [$MetadataTable] was not visible to the connected user."
    }
    $tableInfo = Get-OracleTableInfo @metadataParameters
    $ddl = Get-OracleObjectDdl @ddlParameters
    $metadataResult = [pscustomobject]@{
        Schema      = $tableInfo.Schema
        Table       = $tableInfo.Table
        RowCount    = $rowCount.RowCount
        ListedObjectCount = $listedObjects.Count
        ColumnCount = $tableInfo.ColumnCount
        IndexCount  = $tableInfo.IndexCount
        DdlLength   = $ddl.Length
    }
}

[pscustomobject]@{
    Success         = $true
    ProfileName     = $ProfileName
    DatabaseName    = $server.DatabaseName
    DatabaseUniqueName = $server.DatabaseUniqueName
    ServiceName     = $server.ServiceName
    ServerHost      = $server.ServerHost
    SessionUser     = $server.SessionUser
    ServerTime      = $scalar
    ConnectionAttempts = $wait.Attempts
    InvalidObjectCount = $invalidObjects.Count
    BoundedRowCount = $rows.Count
    CsvPath         = $csvPath
    CsvRowCount     = $export.RowCount
    Metadata        = $metadataResult
}
