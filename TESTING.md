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
- help discovery for selected commands

## Suggested Manual Smoke Tests

Use a known-good Oracle data source and credential.

### Import and configuration

```powershell
Import-Module .\PSOracleTools.psd1 -Force
Initialize-OracleClient | Format-List *
Get-OracleModuleConfiguration | Format-List *
```

### Connection

```powershell
Test-OracleConnection -ProfileName 'ProdLow' | Format-List *
```

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
