<#
.SYNOPSIS
Runs an Oracle stored procedure.

.DESCRIPTION
Builds and executes an anonymous PL/SQL block for an Oracle stored procedure.
The procedure name must be an unquoted one-, two-, or three-part Oracle identifier.
Parameters are bound by name and may be supplied as a hashtable or OracleParameter objects.
Uses the same connection and auto-commit behavior as Invoke-OraclePlSql.

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

.PARAMETER Procedure
Oracle procedure name, optionally qualified as package.procedure or schema.package.procedure.

.PARAMETER Parameters
Optional bind parameters supplied as a hashtable or OracleParameter objects.

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
Includes generated PL/SQL text in log entries.

.PARAMETER LogParameters
Includes parameter names and types in log entries.

.PARAMETER OutputAsProperties
Adds non-input output parameters as top-level properties on the returned object.

.EXAMPLE
Invoke-OracleProcedure -ProfileName 'ProdLow' -Procedure 'ps_tools.movie_pkg.load_movies' -Parameters @{ batch_id = 42 }

Executes a stored procedure using a saved connection profile.

.EXAMPLE
$outCount = New-OracleParameter -Name 'movie_count' -OracleDbType Int32 -Direction Output
Invoke-OracleProcedure -ProfileName 'ProdLow' -Procedure 'ps_tools.movie_pkg.get_movie_count' -Parameters @($outCount) -OutputAsProperties

Executes a stored procedure and returns its output parameter.
#>
function Invoke-OracleProcedure {
    [CmdletBinding(DefaultParameterSetName = 'ByConnectionString', SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

        [Parameter(Mandatory)]
        [Alias('ProcedureName')]
        [string]$Procedure,

        [Parameter()]
        $Parameters,

        [Parameter()]
        [int]$CommandTimeout = 300,

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
        [switch]$LogParameters,

        [Parameter()]
        [switch]$OutputAsProperties
    )

    $identifierPattern = '^[A-Za-z][A-Za-z0-9_$#]*(\.[A-Za-z][A-Za-z0-9_$#]*){0,2}$'
    if ($Procedure -notmatch $identifierPattern) {
        throw 'Procedure must be an unquoted Oracle identifier with up to three dot-separated parts.'
    }

    $shouldProcessTarget = switch ($PSCmdlet.ParameterSetName) {
        'ByProfileName' { "procedure [$Procedure] through profile [$ProfileName]" }
        'ByCredential' { "procedure [$Procedure] on data source [$DataSource]" }
        'ByCredentialName' { "procedure [$Procedure] on data source [$CredentialDataSource]" }
        default { "procedure [$Procedure] through the supplied connection string" }
    }

    if (-not $PSCmdlet.ShouldProcess($shouldProcessTarget, 'Execute Oracle procedure')) {
        return
    }

    $parameterNames = @()
    if ($Parameters -is [hashtable]) {
        $parameterNames = @($Parameters.Keys | ForEach-Object { [string]$_ })
    }
    elseif ($null -ne $Parameters) {
        $parameterNames = @($Parameters | ForEach-Object { [string]$_.ParameterName })
    }

    $bindNamePattern = '^[A-Za-z][A-Za-z0-9_$#]*$'
    $bindNames = @(
        $parameterNames | ForEach-Object {
            $name = $_.TrimStart(':')
            if ($name -notmatch $bindNamePattern) {
                throw "Parameter name '$($_)' is not a valid Oracle bind name."
            }
            $name
        }
    )

    if (@($bindNames | Select-Object -Unique).Count -ne $bindNames.Count) {
        throw 'Procedure parameter names must be unique.'
    }

    $arguments = @($bindNames | ForEach-Object { '{0} => :{0}' -f $_ })
    $plSql = if ($arguments.Count -gt 0) {
        'begin {0}({1}); end;' -f $Procedure, ($arguments -join ', ')
    }
    else {
        'begin {0}; end;' -f $Procedure
    }

    $invokeParams = @{
        PlSql   = $plSql
        Confirm = $false
    }

    foreach ($name in 'Parameters', 'CommandTimeout', 'CredentialStorePath', 'ProfileStorePath', 'Log', 'LogPath', 'LogSql', 'LogParameters', 'OutputAsProperties') {
        if ($PSBoundParameters.ContainsKey($name)) {
            $invokeParams[$name] = $PSBoundParameters[$name]
        }
    }

    switch ($PSCmdlet.ParameterSetName) {
        'ByConnectionString' { $invokeParams.ConnectionString = $ConnectionString }
        'ByCredential' {
            $invokeParams.Credential = $Credential
            $invokeParams.DataSource = $DataSource
        }
        'ByCredentialName' {
            $invokeParams.CredentialName = $CredentialName
            $invokeParams.CredentialDataSource = $CredentialDataSource
        }
        'ByProfileName' { $invokeParams.ProfileName = $ProfileName }
    }

    $result = Invoke-OraclePlSql @invokeParams
    $result.PSObject.TypeNames.Insert(0, 'PSOracleTools.ProcedureResult')
    $result.Operation = 'Invoke-OracleProcedure'
    $result | Add-Member -NotePropertyName Procedure -NotePropertyValue $Procedure
    return $result
}
