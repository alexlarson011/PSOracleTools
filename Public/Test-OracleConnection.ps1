<#
.SYNOPSIS
Tests connectivity to an Oracle database.

.DESCRIPTION
Attempts to open an Oracle connection and run a simple scalar query against dual.
Supports a raw connection string, a PSCredential, or a saved credential name.
Optional logging writes concise operational entries to the information stream and/or a file.

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

.PARAMETER ConnectionTimeout
Connection timeout in seconds.

.PARAMETER CredentialStorePath
Optional custom path to the credential store JSON file.

.PARAMETER Log
Writes operational log entries to the information stream.

.PARAMETER LogPath
Optional log file path. When supplied, log entries are also appended to the file.

.EXAMPLE
Test-OracleConnection -Credential $cred -DataSource 'mydb_low'

Tests an Oracle connection using a PSCredential.

.EXAMPLE
Test-OracleConnection -ProfileName 'ProdLow'

Tests a connection using a saved connection profile.
#>
function Test-OracleConnection {
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
        [int]$ConnectionTimeout = 15,

        [Parameter()]
        [string]$CredentialStorePath,

        [Parameter()]
        [string]$ProfileStorePath,

        [Parameter()]
        [switch]$Log,

        [Parameter()]
        [string]$LogPath
    )

    $startedOn = Get-Date
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $connection = $null
    $command = $null
    $userName = $null
    $targetDataSource = $null
    $operationSucceeded = $false
    $resolvedProfile = $null

    try {
        if ($PSCmdlet.ParameterSetName -eq 'ByConnectionString') {
            $cs = $ConnectionString
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByCredential') {
            $userName = $Credential.UserName
            $targetDataSource = $DataSource
            $cs = New-OracleConnectionString -DataSource $DataSource -UserId $Credential.UserName -Password ($Credential.GetNetworkCredential().Password) -ConnectionTimeout $ConnectionTimeout
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByCredentialName') {
            $resolvedCredential = Resolve-OracleCredential -CredentialName $CredentialName -CredentialStorePath $CredentialStorePath
            $userName = $resolvedCredential.UserName
            $targetDataSource = $CredentialDataSource
            $cs = New-OracleConnectionString -DataSource $CredentialDataSource -UserId $resolvedCredential.UserName -Password ($resolvedCredential.GetNetworkCredential().Password) -ConnectionTimeout $ConnectionTimeout
        }
        else {
            $resolvedProfile = Resolve-OracleConnectionProfile -ProfileName $ProfileName -ProfileStorePath $ProfileStorePath

            if (-not $PSBoundParameters.ContainsKey('CredentialStorePath') -and $resolvedProfile.CredentialStorePath) {
                $CredentialStorePath = [string]$resolvedProfile.CredentialStorePath
            }
            if (-not $PSBoundParameters.ContainsKey('ConnectionTimeout') -and $resolvedProfile.ConnectionTimeout) {
                $ConnectionTimeout = [int]$resolvedProfile.ConnectionTimeout
            }
            if (-not $PSBoundParameters.ContainsKey('LogPath') -and $resolvedProfile.LogPath) {
                $LogPath = [string]$resolvedProfile.LogPath
            }

            $resolvedCredential = Resolve-OracleCredential -CredentialName ([string]$resolvedProfile.CredentialName) -CredentialStorePath $CredentialStorePath
            $userName = $resolvedCredential.UserName
            $targetDataSource = [string]$resolvedProfile.DataSource
            $cs = New-OracleConnectionString -DataSource $targetDataSource -UserId $resolvedCredential.UserName -Password ($resolvedCredential.GetNetworkCredential().Password) -ConnectionTimeout $ConnectionTimeout
        }

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Test-OracleConnection started; DataSource={0}; UserName={1}; ConnectionTimeout={2}" -f $targetDataSource, $userName, $ConnectionTimeout)
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText 'select sysdate from dual'
        $result = $command.ExecuteScalar()

        $sw.Stop()
        $operationSucceeded = $true

        New-OracleResult -TypeName 'PSOracleTools.ConnectionTestResult' -Property ([ordered]@{
                Success       = $true
                Operation     = 'Test-OracleConnection'
                ProfileName   = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
                UserName      = $userName
                DataSource    = $connection.DataSource
                ServerVersion = $connection.ServerVersion
                DatabaseTime  = $result
                StartedOn     = $startedOn
                CompletedOn   = Get-Date
                ElapsedMs     = $sw.ElapsedMilliseconds
            })
    }
    catch {
        $sw.Stop()
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Test-OracleConnection failed; DataSource={0}; UserName={1}; ElapsedMs={2}; Error={3}" -f $targetDataSource, $userName, $sw.ElapsedMilliseconds, (Get-OracleExceptionMessage -Exception $_.Exception))
        }

        New-OracleResult -TypeName 'PSOracleTools.ConnectionTestResult' -Property ([ordered]@{
                Success      = $false
                Operation    = 'Test-OracleConnection'
                ProfileName  = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
                UserName     = $userName
                DataSource   = $targetDataSource
                StartedOn    = $startedOn
                CompletedOn  = Get-Date
                ElapsedMs    = $sw.ElapsedMilliseconds
                ErrorMessage = Get-OracleExceptionMessage -Exception $_.Exception
            })
    }
    finally {
        if (($Log -or $LogPath) -and $operationSucceeded) {
            Write-OracleLog -Path $LogPath -Message ("Test-OracleConnection succeeded; DataSource={0}; UserName={1}; ElapsedMs={2}" -f $connection.DataSource, $userName, $sw.ElapsedMilliseconds)
        }

        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
