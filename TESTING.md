# Testing

This module is small enough that a short smoke-test checklist goes a long way.

## Quick Validation

Run from the repository root:

```powershell
.\scripts\Validate-Module.ps1
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
```

### Connection

```powershell
Test-OracleConnection -ProfileName 'ProdLow' | Format-List *
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

### SQL file

```powershell
Invoke-OracleSqlFile `
  -ProfileName 'ProdLow' `
  -Path '.\scripts\sample.sql' `
  -Log
```

### Export

```powershell
Export-OracleCsv `
  -ProfileName 'ProdLow' `
  -Sql 'select movie_id, movie_nm from ps_tools.movies' `
  -Path '.\output\movies.csv'
```

## SQL File Note

`Invoke-OracleSqlFile` executes the contents of a file as one Oracle command text payload.
That works well for many DDL, DML, and PL/SQL scripts.

It is not intended to emulate SQL*Plus or SQLcl script parsing. In particular, it does not currently handle:

- multiple independent SQL statements split and executed one by one
- SQL*Plus directives such as `set`, `spool`, `prompt`, or `whenever sqlerror`
- slash-delimited client script behavior beyond trimming one trailing `/`
