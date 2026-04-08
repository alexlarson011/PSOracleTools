# PSOracleTools

`PSOracleTools` is a PowerShell module for working with Oracle databases through `Oracle.ManagedDataAccess`.
It is designed to keep common Oracle tasks straightforward from scripts and interactive shells:

- initialize the managed Oracle client automatically on import
- connect with a raw connection string, `PSCredential`, or a saved credential name
- run queries, scalar statements, non-query SQL, and PL/SQL blocks
- export result sets to delimited text files
- use wallet and `tnsnames.ora` based connections through `TNS_ADMIN`
- optionally log execution details for automation and troubleshooting

## Requirements

- Windows PowerShell 5.1
- An Oracle data source reachable from the machine
- If using TNS aliases or an Oracle wallet:
  - `TNS_ADMIN` should point to the folder containing `tnsnames.ora` and wallet files

The module ships with `Oracle.ManagedDataAccess.dll` and the managed dependencies it needs in the local `lib` folder.

## Importing The Module

```powershell
Import-Module "C:\Users\alexl\OneDrive\Scripts\PowerShell\Modules\PSOracleTools\PSOracleTools.psd1" -Force
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
$store = 'C:\Secure\oracle-creds.json'

Set-OracleCredential -Name 'ProdLow' -UserName 'APP_USER' -CredentialStorePath $store
Get-OracleCredential -Name 'ProdLow' -CredentialStorePath $store
Remove-OracleCredential -Name 'ProdLow' -CredentialStorePath $store -Confirm:$false
```

You can set a default store path with:

```powershell
$env:PSORACLETOOLS_CREDENTIAL_STORE = 'C:\Secure\oracle-creds.json'
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
  -Path 'C:\Temp\movies.txt' `
  -Delimiter '|' `
  -IncludeHeader
```

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
  -LogPath 'C:\Logs\oracle.log'
```

Logging includes start/success/failure messages, elapsed time, and relevant summary details.
It does not log passwords or decrypted credentials.

## SQL Text Notes

For the SQL-oriented commands, send plain SQL without a trailing semicolon:

```sql
select movie_id, movie_nm
from ps_tools.movies
where movie_id = :movie_id
```

For PL/SQL blocks, internal semicolons are correct:

```sql
begin
  null;
end;
```

Do not include a trailing `/` terminator in command text.

## Help

Each public function includes comment-based help, so you can use:

```powershell
Get-Help Invoke-OracleQuery -Full
Get-Help Export-OracleDelimitedFile -Examples
Get-Help Set-OracleCredential -Detailed
```
