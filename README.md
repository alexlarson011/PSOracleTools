# PSOracleTools

`PSOracleTools` is a PowerShell module for working with Oracle databases through `Oracle.ManagedDataAccess`.
It is designed to keep common Oracle tasks straightforward from scripts and interactive shells:

- initialize the managed Oracle client automatically on import
- connect with a raw connection string, `PSCredential`, or a saved credential name
- store reusable connection profiles with credential, timeout, and logging defaults
- run queries, scalar statements, non-query SQL, and PL/SQL blocks
- execute SQL files, with optional transaction handling for DML scripts
- export result sets to delimited text files
- export result sets to CSV files
- export result sets to native Excel workbooks (`.xlsx`)
- optionally store passwords in a `Microsoft.PowerShell.SecretManagement` vault
- use wallet and `tnsnames.ora` based connections through `TNS_ADMIN`
- optionally log execution details for automation and troubleshooting

## Requirements

- Windows PowerShell 5.1
- An Oracle data source reachable from the machine
- If using TNS aliases or an Oracle wallet:
  - `TNS_ADMIN` should point to the folder containing `tnsnames.ora` and wallet files

The module ships with `Oracle.ManagedDataAccess.dll` and the managed dependencies it needs in the local `lib` folder.
The supported host is 64-bit Windows PowerShell 5.1. Validate the bundled driver against your Oracle server,
wallet, and authentication configuration in a non-production environment before a rollout.

Optional features have their own requirements:

- Secret-backed credentials require `Microsoft.PowerShell.SecretManagement` and a registered vault extension, such as `Microsoft.PowerShell.SecretStore` or `Az.KeyVault`.
- Optional Excel template automation under `.\Optional\ExcelAutomation` requires Microsoft Excel installed on Windows.

## Five-minute quick start

For an interactive session, create a credential and profile once, test it, then run a parameterized query:

```powershell
Import-Module .\PSOracleTools.psd1 -Force

Set-OracleCredential -Name 'DevCred' -UserName 'APP_USER'
Set-OracleConnectionProfile -Name 'Dev' -DataSource 'mydb_low' -CredentialName 'DevCred'
Test-OracleConnection -ProfileName 'Dev'

Invoke-OracleQuery -ProfileName 'Dev' `
  -Sql 'select movie_id, movie_nm from ps_tools.movies where movie_id = :movie_id' `
  -Parameters @{ movie_id = 1 }
```

For unattended jobs, use a registered SecretManagement vault rather than the default local credential store.
Run the job under the same identity that can read that vault, and test it through the scheduler before production use.

## Choosing a connection method

| Method | Best for | Notes |
| --- | --- | --- |
| `-ConnectionString` | Short-lived local experiments | Avoid placing passwords in source code or command history. |
| `-Credential` + `-DataSource` | Interactive scripts | Keeps the password out of the connection-string literal. |
| `-CredentialName` + `-CredentialDataSource` | Reusable scripts on one Windows identity | Uses the credential store selected for that session. |
| `-ProfileName` | Standard scripts and scheduled jobs | Centralizes data source, credential, timeout, and logging defaults. |

Use SecretManagement-backed credentials for service accounts, scheduled tasks, and any situation where a credential needs to be managed outside one interactive Windows profile.

## Validation

You can run a lightweight repo-local validation pass with:

```powershell
.\scripts\Validate-Module.ps1
```

## Command Overview

The module exports these public commands:

- `Initialize-OracleClient`: load the bundled Oracle managed client and report client paths.
- `Get-OracleServerInfo`: verify the connected Oracle database, service, server, and session identity.
- `New-OracleConnectionString`: safely build an Oracle connection string.
- `Test-OracleConnection`: test a raw, credential-based, or profile-based connection.
- `Set-OracleCredential`, `Get-OracleCredential`, `Remove-OracleCredential`: manage saved Oracle credentials.
- `Set-OracleConnectionProfile`, `Get-OracleConnectionProfile`, `Remove-OracleConnectionProfile`: manage reusable connection profiles.
- `Get-OracleModuleConfiguration`, `Set-OracleModuleConfiguration`: inspect or change session-level store paths.
- `Invoke-OracleQuery`: return dynamic row objects for a SQL query.
- `Invoke-OracleScalar`: return a single scalar value.
- `Invoke-OracleNonQuery`: execute SQL that does not return rows.
- `Invoke-OraclePlSql`: execute PL/SQL blocks and capture output parameters.
- `Invoke-OracleProcedure`: execute a stored procedure and capture output parameters.
- `Invoke-OracleSqlFile`: execute supported SQL script files.
- `Export-OracleDelimitedFile`, `Export-OracleCsv`, `Export-OracleExcel`: export query results.
- `New-OracleParameter`: create typed Oracle parameters for queries and PL/SQL.

## Optional Helpers

Optional, non-core helpers live under `.\Optional`.
They are not imported or exported by the module unless you deliberately dot-source them.

- `.\Optional\ExcelAutomation` contains an Excel COM automation helper for filling workbook templates, optionally running macros, and saving workbooks or PDFs. See `.\Optional\ExcelAutomation\README.md` for its separate risk notes and examples.

## JAMS Note

If a script works in a normal `powershell.exe` session on a server but fails only when JAMS runs it through the in-process PowerShell host, use the wrapper at `.\scripts\Invoke-InFreshWindowsPowerShell.ps1` so JAMS launches a fresh Windows PowerShell process instead of hosting the script in-process:

```powershell
.\scripts\Invoke-InFreshWindowsPowerShell.ps1 `
  -ScriptPath 'F:\SCHED_JOBS\Finance\meu\MEUInterfaceLoad.ps1'
```

You can also pass arguments through with `-ScriptArguments @('value1', 'value2')`.

## Importing The Module

```powershell
Import-Module .\PSOracleTools.psd1 -Force
```

Importing the module also initializes the Oracle managed client automatically.
You can inspect the loaded client paths and active module configuration at any time with:

```powershell
Initialize-OracleClient | Format-List *
Get-OracleModuleConfiguration | Format-List *
```

Automatic initialization is intentional and is the compatibility default: scripts that import the module can call
the public commands immediately. It loads assemblies but does not open a database connection. If initialization
fails, run `Initialize-OracleClient` directly to see the full diagnostics.

## Connecting

There are four main connection patterns:

### 1. Raw connection string

```powershell
$cs = New-OracleConnectionString -DataSource 'mydb_low' -UserId 'app_user' -Password 'secret'
Test-OracleConnection -ConnectionString $cs
```

`New-OracleConnectionString` uses Oracle's connection string builder, so values such as passwords containing semicolons are escaped correctly.
For quick interactive use, the data source, user id, and password can also be positional:

```powershell
$cs = New-OracleConnectionString mydb_low app_user secret
```

### 2. PSCredential

```powershell
$cred = Get-Credential
Test-OracleConnection -Credential $cred -DataSource 'mydb_low'
```

### 3. Saved credential name plus data source

```powershell
Set-OracleCredential -Name 'ProdLow' -UserName 'APP_USER'
Test-OracleConnection -CredentialName 'ProdLow' -CredentialDataSource 'mydb_low'
```

The common credential commands accept the credential name positionally:

```powershell
Set-OracleCredential ProdLow APP_USER
Get-OracleCredential ProdLow
Remove-OracleCredential ProdLow -Confirm:$false
```

### 4. Saved connection profile

```powershell
Set-OracleConnectionProfile -Name 'ProdLow' -DataSource 'mydb_low' -CredentialName 'ProdLow'
Test-OracleConnection -ProfileName 'ProdLow'
```

Profiles are usually the cleanest option for repeatable scripts because they keep the data source, credential name, timeouts, and logging defaults in one named record.
The basic profile create/get/remove flow also supports positional names and required values:

```powershell
Set-OracleConnectionProfile ProdLow mydb_low ProdLow
Get-OracleConnectionProfile ProdLow
Remove-OracleConnectionProfile ProdLow -Confirm:$false
```

`New-OracleConnectionString` also exposes pooling and connection timeout options:

```powershell
New-OracleConnectionString `
  -DataSource 'mydb_low' `
  -UserId 'app_user' `
  -Password 'secret' `
  -Pooling $true `
  -MinPoolSize 1 `
  -MaxPoolSize 10 `
  -ConnectionTimeout 30
```

## Credential Storage

Saved credentials are stored as a JSON file containing the user name and an encrypted password string.
By default, the module uses a credential store under the current user's PowerShell tools directory.
If you use SecretManagement-backed credentials, the JSON file stores metadata only and the password lives in the configured vault.

> **Important:** the default encrypted password uses Windows DPAPI for the current Windows user. The credential
> store is not portable to another machine or Windows account, including a scheduler running as a service account.
> Do not copy the JSON store between hosts. Use SecretManagement for scheduled or multi-host automation.

You can also use a custom credential store path:

```powershell
$store = '.\config\oracle-creds.json'

Set-OracleCredential -Name 'ProdLow' -UserName 'APP_USER' -CredentialStorePath $store
Get-OracleCredential -Name 'ProdLow' -CredentialStorePath $store
Remove-OracleCredential -Name 'ProdLow' -CredentialStorePath $store -Confirm:$false
```

You can set a default store path with:

```powershell
$env:PSORACLETOOLS_CREDENTIAL_STORE = '.\config\oracle-creds.json'
```

You can inspect or override the active module-level store paths for the current session with:

```powershell
Get-OracleModuleConfiguration
Set-OracleModuleConfiguration -CredentialStorePath '.\config\oracle-creds.json'
Set-OracleModuleConfiguration -ResetToDefault
```

### SecretManagement-backed credentials

You can optionally store the password in a registered `Microsoft.PowerShell.SecretManagement` vault.
In that mode, `PSOracleTools` stores only metadata such as the user name, secret name, and vault name in its credential store.

```powershell
Set-OracleCredential `
  -Name 'ProdLow' `
  -Credential $cred `
  -SecretVault 'LocalStore'
```

If `-SecretName` is omitted, the module creates an Azure Key Vault compatible secret name such as `PSOracleTools-ProdLow-1a2b3c4d`.

Azure Key Vault works through the `Az.KeyVault` SecretManagement extension once the vault is registered:

```powershell
Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser
Install-Module Az.KeyVault -Scope CurrentUser

Register-SecretVault `
  -Name 'AzKV' `
  -ModuleName Az.KeyVault `
  -VaultParameters @{
      AZKVaultName  = 'my-key-vault'
      SubscriptionId = '00000000-0000-0000-0000-000000000000'
  }

Set-OracleCredential `
  -Name 'ProdLow' `
  -Credential $cred `
  -SecretVault 'AzKV'
```

Remove the metadata only:

```powershell
Remove-OracleCredential -Name 'ProdLow'
```

Remove both the metadata and the backing secret:

```powershell
Remove-OracleCredential -Name 'ProdLow' -RemoveSecret -Confirm:$false
```

## Connection Profiles

Connection profiles store non-secret defaults such as:

- `DataSource`
- `CredentialName`
- `CredentialStorePath`
- `CommandTimeout`
- `ConnectionTimeout`
- `LogPath`
- `LogSql`
- `LogParameters`

Create a profile:

```powershell
Set-OracleConnectionProfile `
  -Name 'ProdLow' `
  -DataSource 'mydb_low' `
  -CredentialName 'ProdCred' `
  -CommandTimeout 60 `
  -ConnectionTimeout 15 `
  -LogPath '.\logs\oracle.log'
```

Use a profile:

```powershell
Test-OracleConnection -ProfileName 'ProdLow'

# Confirms the database, service, host, and Oracle session identity actually reached.
Get-OracleServerInfo -ProfileName 'ProdLow' | Format-List *

Invoke-OracleQuery `
  -ProfileName 'ProdLow' `
  -Sql 'select movie_id, movie_nm from ps_tools.movies'
```

List or remove profiles:

```powershell
Get-OracleConnectionProfile
Remove-OracleConnectionProfile -Name 'ProdLow' -Confirm:$false
```

You can also set a default profile store path with:

```powershell
$env:PSORACLETOOLS_PROFILE_STORE = '.\config\oracle-profiles.json'
```

The module initializes both store paths on import and, by default, uses:

```text
%APPDATA%\PSOracleTools\credentials.json
%APPDATA%\PSOracleTools\profiles.json
```

You can override either path for the current session without passing it to every command:

```powershell
Set-OracleModuleConfiguration -ProfileStorePath '.\config\oracle-profiles.json'
Invoke-OracleQuery -ProfileName 'ProdLow' -Sql 'select sysdate from dual'
```

## Timeouts

`ConnectionTimeout` controls how long the driver waits while opening a connection.
It can be supplied to `New-OracleConnectionString`, `Test-OracleConnection`, or stored on a connection profile.

`CommandTimeout` controls how long Oracle commands may run after a connection is open.
Query, scalar, non-query, PL/SQL, SQL-file, and export commands all accept `-CommandTimeout`, and profiles can store a default command timeout.

## Query Examples

### Scalar

```powershell
Invoke-OracleScalar `
  -CredentialName 'ProdLow' `
  -CredentialDataSource 'mydb_low' `
  -Sql 'select count(*) from ps_tools.movies'
```

## Result Objects

`Invoke-OracleQuery` intentionally returns dynamic row objects whose properties match the selected columns.
Operational commands return stable, typed status objects with common fields such as:

- `Success`
- `Operation`
- `DataSource`
- `ProfileName`
- `StartedOn`
- `CompletedOn`
- `ElapsedMs`

For example, export commands return `PSOracleTools.CsvExportResult`, `PSOracleTools.DelimitedExportResult`, or `PSOracleTools.ExcelExportResult`.
`Invoke-OracleSqlFile` returns `PSOracleTools.SqlFileResult`, with nested `PSOracleTools.SqlFileStatementResult` objects in `Statements`.

`Invoke-OraclePlSql` keeps output parameters in a stable `OutputParameters` hashtable by default.
For interactive use, add `-OutputAsProperties` to also expose output parameters as top-level properties:

```powershell
Invoke-OraclePlSql `
  -ProfileName 'ProdLow' `
  -PlSql 'begin select count(*) into :movie_count from ps_tools.movies; end;' `
  -Parameters @($outCount) `
  -OutputAsProperties
```

### Query

```powershell
Invoke-OracleQuery `
  -CredentialName 'ProdLow' `
  -CredentialDataSource 'mydb_low' `
  -Sql @"
select movie_id, movie_nm
from ps_tools.movies
order by movie_id
fetch first 5 rows only
"@
```

For interactive exploration, use `-MaxRows` to bound the number of in-memory result objects:

```powershell
Invoke-OracleQuery -ProfileName 'ProdLow' -Sql 'select * from ps_tools.movies order by movie_id' -MaxRows 100
```

### Parameterized query

```powershell
$p = New-OracleParameter -Name 'movie_id' -Value 1 -OracleDbType Int32
$p = New-OracleParameter movie_id 1 Int32

Invoke-OracleQuery `
  -CredentialName 'ProdLow' `
  -CredentialDataSource 'mydb_low' `
  -Sql @"
select movie_id, movie_nm
from ps_tools.movies
where movie_id = :movie_id
"@ `
  -Parameters @($p)
```

For simple input parameters, you can also pass a hashtable:

```powershell
Invoke-OracleQuery `
  -ProfileName 'ProdLow' `
  -Sql 'select movie_id, movie_nm from ps_tools.movies where movie_id = :movie_id' `
  -Parameters @{ movie_id = 1 }
```

Use `New-OracleParameter` when you need an explicit Oracle type, parameter size, or non-input direction such as `Output`.

## Positional Parameter Notes

Short positional forms are supported for the commands where the argument order is obvious:

- `Set-OracleCredential ProdLow APP_USER`
- `Set-OracleCredential ProdLow $cred`
- `Get-OracleCredential ProdLow`
- `Remove-OracleCredential ProdLow -Confirm:$false`
- `Set-OracleConnectionProfile ProdLow mydb_low ProdLow`
- `Get-OracleConnectionProfile ProdLow`
- `Remove-OracleConnectionProfile ProdLow -Confirm:$false`
- `New-OracleConnectionString mydb_low app_user secret`
- `New-OracleParameter movie_id 1 Int32`

Connection commands such as `Invoke-OracleQuery`, `Invoke-OracleSqlFile`, and `Test-OracleConnection` support several different connection styles, so their connection arguments are clearer when named.

## Non-Query And PL/SQL Examples

### Non-query SQL

```powershell
Invoke-OracleNonQuery `
  -CredentialName 'ProdLow' `
  -CredentialDataSource 'mydb_low' `
  -Sql 'update ps_tools.movies set movie_nm = :movie_nm where movie_id = :movie_id' `
  -Parameters @{
      movie_nm = 'Updated Name'
      movie_id = 1
  }
```

### PL/SQL With Output Parameter

```powershell
$outCount = New-OracleParameter -Name 'movie_count' -OracleDbType Int32 -Direction Output

Invoke-OraclePlSql `
  -CredentialName 'ProdLow' `
  -CredentialDataSource 'mydb_low' `
  -PlSql @"
begin
  select count(*)
    into :movie_count
    from ps_tools.movies;
end;
"@ `
  -Parameters @($outCount)
```

### SQL file execution

```powershell
Invoke-OracleSqlFile `
  -ProfileName 'ProdLow' `
  -Path '.\scripts\refresh_movies.sql' `
  -Log `
  -LogPath '.\logs\oracle.log'
```

### Stored procedure

`Invoke-OracleProcedure` creates the anonymous PL/SQL block for an unquoted procedure name.
Procedure names may be qualified as `procedure`, `package.procedure`, or `schema.package.procedure`.
Its parameters are bound by name, and it follows the module's normal ODP.NET auto-commit behavior.

```powershell
Invoke-OracleProcedure `
  -ProfileName 'ProdLow' `
  -Procedure 'ps_tools.movie_pkg.load_movies' `
  -Parameters @{ batch_id = 42 }
```

`Invoke-OracleSqlFile` parses and executes supported statements in order on one Oracle connection.
It supports semicolon-terminated SQL statements and PL/SQL-style blocks terminated by a slash on its own line.
It skips common client-side directives such as `set`, `spool`, `prompt`, `define`, `undefine`, `remark`, and `whenever`.
It is still not a full SQL*Plus-style script runner and does not process commands such as `@child.sql`.

Preview a script before execution—no connection arguments are needed for this mode:

```powershell
Invoke-OracleSqlFile -Path '.\scripts\load_movies.sql' -Preview |
  Select-Object -ExpandProperty Statements |
  Format-Table Index, Kind, IsDdl, Text -Wrap
```

For data-load or refresh scripts, you can run all statements in one transaction:

```powershell
Invoke-OracleSqlFile `
  -ProfileName 'ProdLow' `
  -Path '.\scripts\load_movies.sql' `
  -UseTransaction
```

When `-UseTransaction` is supplied, the command commits only after every statement succeeds and rolls back if any statement fails.
Because Oracle can implicitly commit DDL, obvious DDL/DCL statements such as `create`, `alter`, `drop`, `truncate`, `grant`, and `revoke` are blocked with `-UseTransaction` unless you also pass `-AllowDdlInTransaction`.

## Export Example

```powershell
Export-OracleDelimitedFile `
  -CredentialName 'ProdLow' `
  -CredentialDataSource 'mydb_low' `
  -Sql @"
select movie_id, movie_nm
from ps_tools.movies
order by movie_id
"@ `
  -Path '.\output\movies.txt' `
  -Delimiter '|' `
  -IncludeHeader `
  -TrailingDelimiter
```

You can also load query text from a file with `-SqlPath`, protect existing files with `-NoClobber`, and use `-Force` when you intentionally want to overwrite:

```powershell
Export-OracleDelimitedFile `
  -ProfileName 'ProdLow' `
  -SqlPath '.\queries\movies.sql' `
  -Path '.\output\movies.txt' `
  -IncludeHeader `
  -NoClobber
```

### Fixed-width export

Use `-FixedWidth` for files whose column widths are produced in SQL with `LPAD` or `RPAD`.
It writes the selected values directly next to each other: no delimiters, quotes, or quote escaping are added.
Do not use `-QuoteAll` or `-TrailingDelimiter` with this option.
Delimited exports use UTF-8 with a byte order mark (BOM) by default. Use `-Encoding Utf8NoBom`
when the receiving system requires UTF-8 without a BOM.

```powershell
Export-OracleDelimitedFile `
  -ProfileName 'ProdLow' `
  -Sql @"
select rpad(movie_id, 10) as movie_id,
       rpad(movie_nm, 40) as movie_nm
from ps_tools.movies
order by movie_id
"@ `
  -Path '.\output\movies.txt' `
  -FixedWidth `
  -Encoding Utf8NoBom
```

### CSV export

```powershell
Export-OracleCsv `
  -ProfileName 'ProdLow' `
  -Sql @"
select movie_id, movie_nm
from ps_tools.movies
order by movie_id
"@ `
  -Path '.\output\movies.csv' `
  -DateTimeFormat 'yyyy-MM-dd HH:mm:ss' `
  -Culture 'en-US'
```

### Excel export

```powershell
Export-OracleExcel `
  -ProfileName 'ProdLow' `
  -Sql @"
select movie_id, movie_nm, release_dt
from ps_tools.movies
order by movie_id
"@ `
  -Path '.\output\movies.xlsx' `
  -WorksheetName 'Movies'
```

`Export-OracleExcel` creates a valid `.xlsx` workbook without requiring Microsoft Excel.
By default it includes a plain header row and sizes columns to fit the exported content.
Auto-filtering, frozen panes, and bold headers are available as opt-in options.
The export result includes row count, column count, file size, and elapsed time.

Useful options include:

- `-SqlPath '.\queries\report.sql'`
- `-NoClobber`
- `-Force`
- `-IncludeHeader:$false`
- `-BoldHeader`
- `-WorksheetName 'MySheet'`
- `-AutoFilter`
- `-FreezeHeaderRow`
- `-AutoSizeColumns:$false`
- `-MaxColumnWidth 40`

Delimited and CSV exports also support:

- `-DateFormat 'yyyy-MM-dd'`
- `-DateTimeFormat 'yyyy-MM-dd HH:mm:ss'`
- `-Culture 'en-US'`

Delimited exports also support `-Encoding Utf8Bom` (default) and `-Encoding Utf8NoBom`.

## Logging

The execution commands support optional operational logging:

- `-Log`
- `-LogPath`
- `-LogSql`
- `-LogParameters`

Example:

```powershell
Invoke-OracleQuery `
  -CredentialName 'ProdLow' `
  -CredentialDataSource 'mydb_low' `
  -Sql 'select movie_id, movie_nm from ps_tools.movies' `
  -Log `
  -LogPath '.\logs\oracle.log'
```

Logging includes start/success/failure messages, elapsed time, and relevant summary details.
It does not log passwords or decrypted credentials.

`-LogSql` can still expose sensitive business data when SQL literals, comments, object names, or filters are logged.
`-LogParameters` logs names and types, not values. Keep SQL logging disabled by default, restrict access to log
files, and avoid enabling `LogSql` as a profile default unless the target environment is approved for it.

## Safety for write operations

`Invoke-OracleNonQuery`, `Invoke-OraclePlSql`, `Invoke-OracleProcedure`, `Invoke-OracleSqlFile`, and the profile
and credential setters support PowerShell's common `-WhatIf` and `-Confirm` parameters. Use `-WhatIf` to verify
the target and action without opening an Oracle connection or changing a credential/profile store:

```powershell
Invoke-OracleNonQuery -ProfileName 'ProdLow' `
  -Sql 'delete from ps_tools.movies where movie_id = :movie_id' `
  -Parameters @{ movie_id = 99 } `
  -WhatIf
```

`Invoke-OracleSqlFile -WhatIf` still reads and parses the file so unsupported syntax and DDL transaction guards
are reported before a deployment.

## Troubleshooting

- **TNS alias or wallet connection fails:** verify `TNS_ADMIN` for the exact account that starts PowerShell or the scheduler, and confirm it can read `tnsnames.ora` and wallet files.
- **Works interactively but fails in a scheduler:** compare the Windows identity, 64-bit PowerShell host, `TNS_ADMIN`, and SecretManagement vault access. The JAMS wrapper below is useful for in-process host issues.
- **Oracle assembly cannot load:** run `Initialize-OracleClient` and `.\scripts\Test-OracleAssemblyDependencies.ps1 -TryModuleImport` to collect dependency diagnostics.
- **SQL file behaves differently from SQL*Plus/SQLcl:** this command intentionally supports statement boundaries and a limited directive set; it does not process includes, substitution variables, or full client commands.

## SQL Text Notes

For the SQL-oriented commands, a single trailing semicolon is now tolerated and removed automatically for plain SQL:

```sql
select movie_id, movie_nm
from ps_tools.movies
where movie_id = :movie_id;
```

For PL/SQL blocks, internal semicolons are correct:

```sql
begin
  null;
end;
```

For direct command text, do not include a trailing `/` terminator.
For `Invoke-OracleSqlFile`, a slash on its own line is supported as a PL/SQL block terminator.

## Help

Each public function includes comment-based help, so you can use:

```powershell
Get-Help Invoke-OracleQuery -Full
Get-Help Export-OracleDelimitedFile -Examples
Get-Help Set-OracleCredential -Detailed
```
