# PSOracleTools

`PSOracleTools` is a PowerShell module for working with Oracle databases through `Oracle.ManagedDataAccess`.
It is designed to keep common Oracle tasks straightforward from scripts and interactive shells:

- initialize the managed Oracle client automatically on import
- connect with a raw connection string, `PSCredential`, or a saved credential name
- run queries, scalar statements, non-query SQL, and PL/SQL blocks
- execute SQL files
- export result sets to delimited text files
- export result sets to CSV files
- export result sets to native Excel workbooks (`.xlsx`)
- use wallet and `tnsnames.ora` based connections through `TNS_ADMIN`
- optionally log execution details for automation and troubleshooting

## Requirements

- Windows PowerShell 5.1
- An Oracle data source reachable from the machine
- If using TNS aliases or an Oracle wallet:
  - `TNS_ADMIN` should point to the folder containing `tnsnames.ora` and wallet files

The module ships with `Oracle.ManagedDataAccess.dll` and the managed dependencies it needs in the local `lib` folder.

## Validation

You can run a lightweight repo-local validation pass with:

```powershell
.\scripts\Validate-Module.ps1
```

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
You can inspect the active configuration at any time with:

```powershell
Initialize-OracleClient | Format-List *
```

## Connecting

There are three main connection patterns:

### 1. Raw connection string

```powershell
$cs = New-OracleConnectionString -DataSource 'mydb_low' -UserId 'app_user' -Password 'secret'
Test-OracleConnection -ConnectionString $cs
```

### 2. PSCredential

```powershell
$cred = Get-Credential
Test-OracleConnection -Credential $cred -DataSource 'mydb_low'
```

### 3. Saved credential name

```powershell
Set-OracleCredential -Name 'ProdLow' -UserName 'APP_USER'
Test-OracleConnection -CredentialName 'ProdLow' -CredentialDataSource 'mydb_low'
```

## Credential Storage

Saved credentials are stored as a JSON file containing the user name and an encrypted password string.
By default, the module uses a credential store under the current user's PowerShell tools directory.

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

## Query Examples

### Scalar

```powershell
Invoke-OracleScalar `
  -CredentialName 'ProdLow' `
  -CredentialDataSource 'mydb_low' `
  -Sql 'select count(*) from ps_tools.movies'
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

### Parameterized query

```powershell
$p = New-OracleParameter -Name 'movie_id' -Value 1 -OracleDbType Int32

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

`Invoke-OracleSqlFile` parses and executes supported statements in order on one Oracle connection.
It supports semicolon-terminated SQL statements and PL/SQL-style blocks terminated by a slash on its own line.
It skips common client-side directives such as `set`, `spool`, `prompt`, `define`, `undefine`, `remark`, and `whenever`.
It is still not a full SQL*Plus-style script runner and does not process commands such as `@child.sql`.

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
