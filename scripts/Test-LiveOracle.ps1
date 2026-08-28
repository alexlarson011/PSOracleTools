<#
.SYNOPSIS
Runs a read-only smoke test against an Oracle connection profile.

.DESCRIPTION
Imports the local PSOracleTools module and verifies connection, Oracle server identity, scalar queries, bounded
queries, and CSV export. It does not issue DDL, DML, PL/SQL, or stored-procedure calls.

.PARAMETER ProfileName
Saved PSOracleTools connection profile to test.

.PARAMETER OutputDirectory
Directory where the temporary smoke-test CSV file will be written. Defaults to a unique temporary directory.

.EXAMPLE
.\scripts\Test-LiveOracle.ps1 -ProfileName 'ProdLow'

Runs the read-only smoke test using the ProdLow connection profile.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProfileName,

    [Parameter()]
    [string]$OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) ('PSOracleTools-LiveTest-' + [guid]::NewGuid().ToString('N')))
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

$server = Get-OracleServerInfo -ProfileName $ProfileName
$scalar = Invoke-OracleScalar -ProfileName $ProfileName -Sql 'select sysdate from dual'
$rows = @(Invoke-OracleQuery -ProfileName $ProfileName -Sql 'select level as row_number from dual connect by level <= 3' -MaxRows 2)
if ($rows.Count -ne 2) {
    throw "Expected -MaxRows 2 to return two rows, but received [$($rows.Count)]."
}

$csvPath = Join-Path $OutputDirectory 'oracle-smoke-test.csv'
$export = Export-OracleCsv -ProfileName $ProfileName -Sql 'select level as row_number from dual connect by level <= 3' -Path $csvPath -NoClobber
if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
    throw "CSV export was not created at [$csvPath]."
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
    BoundedRowCount = $rows.Count
    CsvPath         = $csvPath
    CsvRowCount     = $export.RowCount
}
