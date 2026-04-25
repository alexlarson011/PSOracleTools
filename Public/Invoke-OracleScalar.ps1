<#
.SYNOPSIS
Runs a query that returns a single value.

.DESCRIPTION
Executes SQL and returns the first column of the first row from the result set.
Supports raw connection strings, PSCredential input, or saved credential names.

.PARAMETER Sql
SQL text to execute.

.PARAMETER Parameters
Optional bind parameters supplied as a hashtable or OracleParameter objects.

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
Includes SQL text in log entries.

.PARAMETER LogParameters
Includes parameter names and types in log entries.

.EXAMPLE
Invoke-OracleScalar -ProfileName 'ProdLow' -Sql 'select count(*) from ps_tools.movies'

Returns a single scalar value using a saved connection profile.
#>
function Invoke-OracleScalar {
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
        [string]$Sql,

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
        [switch]$LogParameters
    )

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

        $normalizedSql = Normalize-OracleCommandText -Text $Sql -Mode Sql

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleScalar started; DataSource={0}; CommandTimeout={1}" -f $targetDataSource, $CommandTimeout)
            if ($LogSql) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OracleScalar SQL: {0}" -f (ConvertTo-OracleLogText -Text $normalizedSql))
            }
            if ($LogParameters) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OracleScalar Parameters: {0}" -f ((Get-OracleParameterSummary -Parameters $Parameters) -join ', '))
            }
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText $normalizedSql -CommandTimeout $CommandTimeout
        Add-OracleParameters -Command $command -Parameters $Parameters

        $result = $command.ExecuteScalar()
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleScalar succeeded; DataSource={0}; Result={1}" -f $connection.DataSource, $result)
        }
        return $result
    }
    catch {
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Invoke-OracleScalar failed; DataSource={0}; Error={1}" -f $targetDataSource, (Get-OracleExceptionMessage -Exception $_.Exception))
        }
        throw
    }
    finally {
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
