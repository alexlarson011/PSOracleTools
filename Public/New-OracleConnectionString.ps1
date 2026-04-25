<#
.SYNOPSIS
Builds an Oracle connection string for the managed driver.

.DESCRIPTION
Creates a connection string using a data source, user name, password, and optional pooling or timeout settings.
Use the resulting string with the commands that accept -ConnectionString.

.PARAMETER DataSource
Oracle data source or TNS alias.

.PARAMETER UserId
Database user name.

.PARAMETER Password
Database password.

.PARAMETER Pooling
Enables or disables connection pooling.

.PARAMETER MinPoolSize
Minimum pool size when pooling is enabled.

.PARAMETER MaxPoolSize
Maximum pool size when pooling is enabled.

.PARAMETER ConnectionTimeout
Connection timeout in seconds.

.EXAMPLE
New-OracleConnectionString -DataSource 'mydb_low' -UserId 'app_user' -Password 'secret'

Builds a simple Oracle connection string.

.EXAMPLE
New-OracleConnectionString mydb_low app_user secret

Builds a simple Oracle connection string using positional arguments.
#>
function New-OracleConnectionString {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$DataSource,

        [Parameter(Mandatory, Position = 1)]
        [string]$UserId,

        [Parameter(Mandatory, Position = 2)]
        [string]$Password,

        [Parameter(Position = 3)]
        [bool]$Pooling = $true,

        [Parameter(Position = 4)]
        [int]$MinPoolSize = 1,

        [Parameter(Position = 5)]
        [int]$MaxPoolSize = 10
        ,

        [Parameter(Position = 6)]
        [int]$ConnectionTimeout = 30
    )

    $builder = New-Object Oracle.ManagedDataAccess.Client.OracleConnectionStringBuilder
    $builder['User Id'] = $UserId
    $builder['Password'] = $Password
    $builder['Data Source'] = $DataSource
    $builder['Pooling'] = $Pooling
    $builder['Min Pool Size'] = $MinPoolSize
    $builder['Max Pool Size'] = $MaxPoolSize
    $builder['Connection Timeout'] = $ConnectionTimeout

    return $builder.ConnectionString
}
