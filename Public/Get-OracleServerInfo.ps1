<#
.SYNOPSIS
Returns Oracle database and session identity details.

.DESCRIPTION
Queries Oracle's USERENV context to report the connected user, database identity, service name, host, and session ID.
Use this to verify that a profile, wallet, or scheduler account reaches the intended database.

.PARAMETER ConnectionString
Full Oracle connection string.

.PARAMETER Credential
PSCredential used to build the Oracle connection string.

.PARAMETER DataSource
Oracle data source or TNS alias used with -Credential.

.PARAMETER CredentialName
Saved credential name used with -CredentialDataSource.

.PARAMETER CredentialDataSource
Oracle data source or TNS alias used with -CredentialName.

.PARAMETER ProfileName
Saved connection profile name.

.PARAMETER CommandTimeout
Command timeout in seconds.

.PARAMETER CredentialStorePath
Optional custom path to the credential store JSON file.

.PARAMETER ProfileStorePath
Optional custom path to the profile store JSON file.

.PARAMETER Log
Writes operational log entries to the information stream.

.PARAMETER LogPath
Optional log file path.

.PARAMETER LogSql
Includes the diagnostic SQL text in log entries.

.PARAMETER LogParameters
Includes parameter names and types in log entries.

.EXAMPLE
Get-OracleServerInfo -ProfileName 'ProdLow'

Shows the Oracle server and session reached through the ProdLow connection profile.
#>
function Get-OracleServerInfo {
    [CmdletBinding(DefaultParameterSetName = 'ByConnectionString')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByConnectionString')]
        [string]$ConnectionString,

        [Parameter(Mandatory, ParameterSetName = 'ByCredential')]
        [PSCredential]$Credential,

        [Parameter(Mandatory, ParameterSetName = 'ByCredential')]
        [string]$DataSource,

        [Parameter(Mandatory, ParameterSetName = 'ByCredentialName')]
        [string]$CredentialName,

        [Parameter(Mandatory, ParameterSetName = 'ByCredentialName')]
        [string]$CredentialDataSource,

        [Parameter(Mandatory, ParameterSetName = 'ByProfileName')]
        [string]$ProfileName,

        [Parameter()]
        [int]$CommandTimeout = 30,

        [Parameter()]
        [string]$CredentialStorePath,

        [Parameter()]
        [string]$ProfileStorePath,

        [Parameter()]
        [switch]$Log,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [switch]$LogSql,

        [Parameter()]
        [switch]$LogParameters
    )

    $queryParameters = @{
        Sql            = @'
select sys_context('USERENV', 'SESSION_USER') as session_user,
       sys_context('USERENV', 'CURRENT_USER') as current_user,
       sys_context('USERENV', 'DB_UNIQUE_NAME') as db_unique_name,
       sys_context('USERENV', 'DB_NAME') as db_name,
       sys_context('USERENV', 'SERVICE_NAME') as service_name,
       sys_context('USERENV', 'SERVER_HOST') as server_host,
       sys_context('USERENV', 'INSTANCE_NAME') as instance_name,
       sys_context('USERENV', 'SID') as session_id
from dual
'@
        CommandTimeout = $CommandTimeout
        Log            = $Log
        LogSql         = $LogSql
        LogParameters  = $LogParameters
    }

    foreach ($name in 'CredentialStorePath', 'ProfileStorePath', 'LogPath') {
        if ($PSBoundParameters.ContainsKey($name)) {
            $queryParameters[$name] = $PSBoundParameters[$name]
        }
    }

    switch ($PSCmdlet.ParameterSetName) {
        'ByConnectionString' { $queryParameters.ConnectionString = $ConnectionString }
        'ByCredential' {
            $queryParameters.Credential = $Credential
            $queryParameters.DataSource = $DataSource
        }
        'ByCredentialName' {
            $queryParameters.CredentialName = $CredentialName
            $queryParameters.CredentialDataSource = $CredentialDataSource
        }
        'ByProfileName' { $queryParameters.ProfileName = $ProfileName }
    }

    $row = @(Invoke-OracleQuery @queryParameters | Select-Object -First 1)[0]
    if ($null -eq $row) {
        throw 'Oracle server information query returned no rows.'
    }

    $properties = [ordered]@{
        Success      = $true
        Operation    = 'Get-OracleServerInfo'
        ProfileName  = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
        SessionUser  = $row.session_user
        CurrentUser  = $row.current_user
        DatabaseName = $row.db_name
        DatabaseUniqueName = $row.db_unique_name
        ServiceName  = $row.service_name
        ServerHost   = $row.server_host
        InstanceName = $row.instance_name
        SessionId    = $row.session_id
    }

    return New-OracleResult -TypeName 'PSOracleTools.ServerInfoResult' -Property $properties
}
