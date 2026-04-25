<#
.SYNOPSIS
Runs a PL/SQL block.

.DESCRIPTION
Executes a PL/SQL block and returns any non-input parameters as output values.
Supports raw connection strings, PSCredential input, or saved credential names.

.PARAMETER PlSql
PL/SQL block to execute.

.PARAMETER Parameters
Optional bind parameters supplied as OracleParameter objects.

.PARAMETER CommandTimeout
Command timeout in seconds.

.PARAMETER ProfileName
Saved connection profile name.

.PARAMETER CredentialStorePath
Optional custom path to the credential store JSON file.

.PARAMETER Log
Writes operational log entries to the information stream.

.PARAMETER LogPath
Optional log file path.

.PARAMETER LogSql
Includes PL/SQL text in log entries.

.PARAMETER LogParameters
Includes parameter names and types in log entries.

.PARAMETER OutputAsProperties
Adds non-input output parameters as top-level properties on the returned object.

.EXAMPLE
$outCount = New-OracleParameter -Name 'movie_count' -OracleDbType Int32 -Direction Output
Invoke-OraclePlSql -ProfileName 'ProdLow' -PlSql 'begin select count(*) into :movie_count from ps_tools.movies; end;' -Parameters @($outCount)

Executes a PL/SQL block with a saved connection profile and returns output parameters.

.EXAMPLE
Invoke-OraclePlSql -ProfileName 'ProdLow' -PlSql 'begin select count(*) into :movie_count from ps_tools.movies; end;' -Parameters @($outCount) -OutputAsProperties

Returns output parameters as top-level properties in addition to the stable OutputParameters hashtable.
#>
function Invoke-OraclePlSql {
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

        [Parameter(Mandatory)]
        [string]$PlSql,

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

    $startedOn = Get-Date
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $connection = $null
    $command = $null
    $targetDataSource = $null
    $resolvedProfile = $null

    try {
        switch ($PSCmdlet.ParameterSetName) {
            'ByConnectionString' {
                $cs = $ConnectionString
            }
            'ByCredential' {
                $targetDataSource = $DataSource
                $cs = New-OracleConnectionString -DataSource $DataSource -UserId $Credential.UserName -Password ($Credential.GetNetworkCredential().Password)
            }
            'ByCredentialName' {
                $resolvedCredential = Resolve-OracleCredential -CredentialName $CredentialName -CredentialStorePath $CredentialStorePath
                $targetDataSource = $CredentialDataSource
                $cs = New-OracleConnectionString -DataSource $CredentialDataSource -UserId $resolvedCredential.UserName -Password ($resolvedCredential.GetNetworkCredential().Password)
            }
            'ByProfileName' {
                $resolvedProfile = Resolve-OracleConnectionProfile -ProfileName $ProfileName -ProfileStorePath $ProfileStorePath
                if (-not $PSBoundParameters.ContainsKey('CredentialStorePath') -and $resolvedProfile.CredentialStorePath) {
                    $CredentialStorePath = [string]$resolvedProfile.CredentialStorePath
                }
                if (-not $PSBoundParameters.ContainsKey('CommandTimeout') -and $resolvedProfile.CommandTimeout) {
                    $CommandTimeout = [int]$resolvedProfile.CommandTimeout
                }
                if (-not $PSBoundParameters.ContainsKey('LogPath') -and $resolvedProfile.LogPath) {
                    $LogPath = [string]$resolvedProfile.LogPath
                }
                if (-not $PSBoundParameters.ContainsKey('LogSql') -and $resolvedProfile.LogSql) {
                    $LogSql = [bool]$resolvedProfile.LogSql
                }
                if (-not $PSBoundParameters.ContainsKey('LogParameters') -and $resolvedProfile.LogParameters) {
                    $LogParameters = [bool]$resolvedProfile.LogParameters
                }

                $resolvedCredential = Resolve-OracleCredential -CredentialName ([string]$resolvedProfile.CredentialName) -CredentialStorePath $CredentialStorePath
                $targetDataSource = [string]$resolvedProfile.DataSource
                $connectionStringParameters = @{
                    DataSource = $targetDataSource
                    UserId     = $resolvedCredential.UserName
                    Password   = $resolvedCredential.GetNetworkCredential().Password
                }
                if ($resolvedProfile.ConnectionTimeout) {
                    $connectionStringParameters.ConnectionTimeout = [int]$resolvedProfile.ConnectionTimeout
                }
                $cs = New-OracleConnectionString @connectionStringParameters
            }
        }

        $normalizedPlSql = Normalize-OracleCommandText -Text $PlSql -Mode PlSql

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OraclePlSql started; DataSource={0}; CommandTimeout={1}" -f $targetDataSource, $CommandTimeout)
            if ($LogSql) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OraclePlSql Block: {0}" -f (ConvertTo-OracleLogText -Text $normalizedPlSql))
            }
            if ($LogParameters) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OraclePlSql Parameters: {0}" -f ((Get-OracleParameterSummary -Parameters $Parameters) -join ', '))
            }
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText $normalizedPlSql -CommandTimeout $CommandTimeout
        Add-OracleParameters -Command $command -Parameters $Parameters

        [void]$command.ExecuteNonQuery()
        $sw.Stop()

        $outputParameters = @{}
        foreach ($param in $command.Parameters) {
            if ($param.Direction -ne [System.Data.ParameterDirection]::Input) {
                $outputParameters[$param.ParameterName] = ConvertFrom-OracleProviderValue -Value $param.Value
            }
        }

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OraclePlSql succeeded; DataSource={0}; OutputParameterCount={1}; ElapsedMs={2}" -f $connection.DataSource, $outputParameters.Count, $sw.ElapsedMilliseconds)
        }

        $completedOn = Get-Date
        $properties = [ordered]@{
            Success              = $true
            Operation            = 'Invoke-OraclePlSql'
            DataSource           = $connection.DataSource
            ProfileName          = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
            StartedOn            = $startedOn
            CompletedOn          = $completedOn
            ElapsedMs            = $sw.ElapsedMilliseconds
            OutputParameterCount = $outputParameters.Count
            OutputParameters     = $outputParameters
        }

        if ($OutputAsProperties) {
            foreach ($key in ($outputParameters.Keys | Sort-Object)) {
                $propertyName = [string]$key
                if ($properties.Contains($propertyName)) {
                    $propertyName = 'Output_{0}' -f $propertyName
                }
                $properties[$propertyName] = $outputParameters[$key]
            }
        }

        New-OracleResult -TypeName 'PSOracleTools.PlSqlResult' -Property $properties
    }
    catch {
        $sw.Stop()
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Invoke-OraclePlSql failed; DataSource={0}; ElapsedMs={1}; Error={2}" -f $targetDataSource, $sw.ElapsedMilliseconds, (Get-OracleExceptionMessage -Exception $_.Exception))
        }
        throw
    }
    finally {
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
