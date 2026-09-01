<#
.SYNOPSIS
Waits until an Oracle connection succeeds or a timeout is reached.

.DESCRIPTION
Repeatedly calls Test-OracleConnection using the module's standard connection methods. Returns one stable wait
result containing the number of attempts and the final connection test. This is intended for startup scripts,
scheduled work, and deployments where Oracle may become available shortly after the caller starts.

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

.PARAMETER TimeoutSeconds
Maximum approximate number of seconds to wait. An active connection attempt can run until its per-attempt
connection timeout expires.

.PARAMETER RetryIntervalSeconds
Seconds to wait between failed attempts. Fractional seconds are supported.

.PARAMETER ConnectionTimeout
Maximum connection timeout used for each attempt. The value is reduced when less overall wait time remains.

.PARAMETER ThrowOnTimeout
Throws a terminating error instead of returning an unsuccessful result when the wait expires.

.PARAMETER CredentialStorePath
Optional custom path to the credential store JSON file.

.PARAMETER ProfileStorePath
Optional custom path to the profile store JSON file.

.PARAMETER Log
Writes each connection test's operational log entries to the information stream.

.PARAMETER LogPath
Optional log file path.

.EXAMPLE
Wait-OracleConnection -ProfileName 'ProdLow'

Waits up to 60 seconds for the saved profile, retrying every five seconds.

.EXAMPLE
Wait-OracleConnection -ProfileName 'ProdLow' -TimeoutSeconds 300 -RetryIntervalSeconds 10 -ThrowOnTimeout

Waits for up to five minutes and throws if Oracle does not become available.
#>
function Wait-OracleConnection {
    [CmdletBinding(DefaultParameterSetName = 'ByConnectionString', PositionalBinding = $false)]
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
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutSeconds = 60,

        [Parameter()]
        [ValidateRange(0.1, 86400)]
        [double]$RetryIntervalSeconds = 5,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ConnectionTimeout = 5,

        [Parameter()]
        [switch]$ThrowOnTimeout,

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
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $attempts = 0
    $lastTest = $null
    $baseTestParameters = Get-OracleInvocationParameters -BoundParameters $PSBoundParameters -Target ConnectionTest

    while ($true) {
        $attempts++
        $remainingSeconds = [Math]::Max(1, $TimeoutSeconds - $stopwatch.Elapsed.TotalSeconds)
        $attemptParameters = @{} + $baseTestParameters
        $attemptParameters.ConnectionTimeout = [int][Math]::Max(1, [Math]::Min($ConnectionTimeout, [Math]::Ceiling($remainingSeconds)))
        $lastTest = Test-OracleConnection @attemptParameters

        if ($lastTest.Success -or $stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            break
        }

        $remainingMilliseconds = [Math]::Max(1, ($TimeoutSeconds - $stopwatch.Elapsed.TotalSeconds) * 1000)
        $sleepMilliseconds = [int][Math]::Min([int]::MaxValue, [Math]::Min($RetryIntervalSeconds * 1000, $remainingMilliseconds))
        Start-Sleep -Milliseconds $sleepMilliseconds
    }

    $stopwatch.Stop()
    $success = [bool]$lastTest.Success
    $errorMessage = if ($lastTest.PSObject.Properties['ErrorMessage']) { [string]$lastTest.ErrorMessage } else { $null }
    $result = New-OracleResult -TypeName 'PSOracleTools.ConnectionWaitResult' -Property ([ordered]@{
            Success       = $success
            Operation     = 'Wait-OracleConnection'
            ProfileName   = if ($PSCmdlet.ParameterSetName -eq 'ByProfileName') { $ProfileName } else { $null }
            DataSource    = if ($lastTest.PSObject.Properties['DataSource']) { $lastTest.DataSource } else { $null }
            UserName      = if ($lastTest.PSObject.Properties['UserName']) { $lastTest.UserName } else { $null }
            ServerVersion = if ($lastTest.PSObject.Properties['ServerVersion']) { $lastTest.ServerVersion } else { $null }
            DatabaseTime  = if ($lastTest.PSObject.Properties['DatabaseTime']) { $lastTest.DatabaseTime } else { $null }
            Attempts      = $attempts
            TimedOut      = -not $success
            StartedOn     = $startedOn
            CompletedOn   = Get-Date
            ElapsedMs     = $stopwatch.ElapsedMilliseconds
            ErrorMessage  = $errorMessage
            LastTest      = $lastTest
        })

    if (-not $success -and $ThrowOnTimeout) {
        $detail = if ([string]::IsNullOrWhiteSpace($errorMessage)) { 'The final connection test did not report an error message.' } else { $errorMessage }
        throw "Oracle did not become available within approximately [$TimeoutSeconds] seconds after [$attempts] attempt(s). $detail"
    }

    return $result
}
