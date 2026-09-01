# Testing

This module is small enough that a short smoke-test checklist goes a long way.

## Quick Validation

Run from the repository root:

```powershell
.\scripts\Validate-Module.ps1
```

If a scheduler or automation host is suspect, also test out-of-process execution:

```powershell
.\scripts\Invoke-InFreshWindowsPowerShell.ps1 `
  -ScriptPath '.\your-job-script.ps1'
```

This checks:

- manifest validity
- module import
- exported public commands
- module-level `Get-Help about_PSOracleTools` discovery and command-catalog completeness
- help discovery for selected commands

It does not connect to Oracle. The automated Pester suite covers parsing, duplicate result columns, wrapper defaults,
atomic output replacement, command safety, credential/profile file behavior (including concurrent profile writes),
metadata identifier safety and result grouping, connection retries, and result formatting without requiring a database.
Run it when Pester is installed:

```powershell
Invoke-Pester .\tests
```

## Suggested Manual Smoke Tests

Use a known-good Oracle data source and credential.

### Import and configuration

```powershell
Import-Module .\PSOracleTools.psd1 -Force
Initialize-OracleClient | Format-List *
Get-OracleModuleConfiguration | Format-List *
Get-Help about_PSOracleTools
```

### Connection

```powershell
Test-OracleConnection -ProfileName 'ProdLow' | Format-List *
```

### Read-only live smoke test

After automated checks pass, run the repository helper against a non-production profile first:

```powershell
.\scripts\Test-LiveOracle.ps1 -ProfileName 'ProdLow' -MetadataTable 'movies' | Format-List *
```

It verifies connection, database/session identity, connection waiting, invalid-object inspection, `-MaxRows`, and CSV
export without issuing DDL, DML, PL/SQL, or procedure calls. `-MetadataTable` additionally checks the row-count,
schema-inventory, object, table-information, and DDL helpers against an object owned by the test account. The returned `CsvPath`
identifies the temporary output file for inspection.

### Scheduler identity

Run the same smoke test from the account that will run the scheduled job. Confirm `TNS_ADMIN`, wallet-file access,
and SecretManagement vault access for that account. A DPAPI-backed credential created by one Windows account cannot
be used by another account or host.

### Optional SecretManagement

If `Microsoft.PowerShell.SecretManagement` and a vault extension are configured:

```powershell
$cred = Get-Credential
Set-OracleCredential -Name 'ProdSecret' -Credential $cred -SecretVault 'LocalStore'
Set-OracleConnectionProfile -Name 'ProdSecret' -DataSource 'mydb_low' -CredentialName 'ProdSecret'
Test-OracleConnection -ProfileName 'ProdSecret'
Remove-OracleCredential -Name 'ProdSecret' -RemoveSecret -Confirm:$false
```

### Query

```powershell
Invoke-OracleQuery `
  -ProfileName 'ProdLow' `
  -Sql 'select movie_id, movie_nm from ps_tools.movies fetch first 5 rows only'
```

### Scalar

```powershell
Invoke-OracleScalar `
  -ProfileName 'ProdLow' `
  -Sql 'select count(*) from ps_tools.movies'
```

### Metadata helpers

Use an object owned by the test account so `DBMS_METADATA` privileges are predictable:

```powershell
Get-OracleRowCount -ProfileName 'ProdLow' -Table 'movies' | Format-List *
Get-OracleRowCount -ProfileName 'ProdLow' -Table 'movies' -Estimate | Format-List *
Get-OracleObject -ProfileName 'ProdLow' -ObjectType Table -Name 'movies' | Format-List *
Test-OracleObject -ProfileName 'ProdLow' -Name 'movies' -ObjectType Table | Format-List *

$table = Get-OracleTableInfo -ProfileName 'ProdLow' -Table 'movies'
$table | Format-List Schema, Table, RowEstimate, LastAnalyzed, ColumnCount, IndexCount
$table.Columns | Format-Table Position, Name, DataType, Nullable

Get-OracleInvalidObject -ProfileName 'ProdLow' | Format-Table Schema, Name, ObjectType, ErrorCount
Get-OracleObjectDdl -ProfileName 'ProdLow' -Name 'movies' -ObjectType Table -DdlOnly
Wait-OracleConnection -ProfileName 'ProdLow' -TimeoutSeconds 10 -RetryIntervalSeconds 1 | Format-List *
```

Verify that exact row count matches a direct `COUNT(*)`, schema inventory returns the test table, missing objects
return `Success = True` and `Exists = False`, and table metadata contains the expected columns and indexes. An estimated row count can legitimately be `$null` or
differ from the exact count when statistics are missing or stale.

### PL/SQL

```powershell
$outCount = New-OracleParameter -Name 'movie_count' -OracleDbType Int32 -Direction Output

Invoke-OraclePlSql `
  -ProfileName 'ProdLow' `
  -PlSql 'begin select count(*) into :movie_count from ps_tools.movies; end;' `
  -Parameters @($outCount) `
  -OutputAsProperties
```

### SQL file

```powershell
Invoke-OracleSqlFile `
  -ProfileName 'ProdLow' `
  -Path '.\scripts\sample.sql' `
  -Log

Invoke-OracleSqlFile `
  -ProfileName 'ProdLow' `
  -Path '.\scripts\data-load.sql' `
  -UseTransaction
```

### Export

```powershell
Export-OracleCsv `
  -ProfileName 'ProdLow' `
  -Sql 'select movie_id, movie_nm from ps_tools.movies' `
  -Path '.\output\movies.csv' `
  -DateTimeFormat 'yyyy-MM-dd HH:mm:ss' `
  -Culture 'en-US'

New-Item -Path '.\output' -ItemType Directory -Force | Out-Null
'select movie_id, movie_nm, release_dt from ps_tools.movies' | Set-Content -Path '.\output\movies-query.sql'

Export-OracleExcel `
  -ProfileName 'ProdLow' `
  -SqlPath '.\output\movies-query.sql' `
  -Path '.\output\movies.xlsx' `
  -WorksheetName 'Movies' `
  -NoClobber
```

## SQL File Note

`Invoke-OracleSqlFile` parses and executes supported statements in order on one Oracle connection.
That works well for many DDL, DML, and PL/SQL scripts.

Supported script boundaries:

- SQL statements terminated by `;`
- PL/SQL-style blocks terminated by `/` on its own line

It is not intended to emulate SQL*Plus or SQLcl script parsing. In particular, it does not currently handle:

- SQL*Plus directives such as `set`, `spool`, `prompt`, `define`, `whenever sqlerror`, or `@child.sql`
- broader client-side substitution behavior

When testing `-UseTransaction`, prefer DML-only scripts. Oracle can implicitly commit DDL, so `Invoke-OracleSqlFile -UseTransaction` blocks obvious DDL/DCL unless `-AllowDdlInTransaction` is supplied.

## Write-operation safety check

Before a production run, use `-WhatIf` with the same parameters. It must print the intended action without opening
an Oracle connection or modifying local credential/profile files:

```powershell
Invoke-OracleNonQuery -ProfileName 'ProdLow' `
  -Sql 'delete from ps_tools.movies where movie_id = :movie_id' `
  -Parameters @{ movie_id = 99 } `
  -WhatIf
```
