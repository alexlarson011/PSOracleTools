function Set-OracleClientConfiguration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TnsAdmin = $env:TNS_ADMIN,

        [Parameter()]
        [string]$WalletLocation = $env:TNS_ADMIN
    )

    if ($TnsAdmin) {
        [Oracle.ManagedDataAccess.Client.OracleConfiguration]::TnsAdmin = $TnsAdmin
    }

    if ($WalletLocation) {
        [Oracle.ManagedDataAccess.Client.OracleConfiguration]::WalletLocation = $WalletLocation
    }

    # Disable ODP.NET OpenTelemetry instrumentation in shared-host environments
    # where DiagnosticSource/OpenTelemetry assembly resolution is outside the
    # module's control (for example, JAMS-hosted Windows PowerShell jobs).
    [Oracle.ManagedDataAccess.Client.OracleConfiguration]::OpenTelemetryTracing = $false
    [Oracle.ManagedDataAccess.Client.OracleConfiguration]::DatabaseOpenTelemetryTracing = $false

    [Oracle.ManagedDataAccess.Client.OracleConfiguration]::SSLServerDNMatch = $true

    [pscustomobject]@{
        TnsAdmin                    = [Oracle.ManagedDataAccess.Client.OracleConfiguration]::TnsAdmin
        WalletLocation              = [Oracle.ManagedDataAccess.Client.OracleConfiguration]::WalletLocation
        OpenTelemetryTracing        = [Oracle.ManagedDataAccess.Client.OracleConfiguration]::OpenTelemetryTracing
        DatabaseOpenTelemetryTracing = [Oracle.ManagedDataAccess.Client.OracleConfiguration]::DatabaseOpenTelemetryTracing
        SSLServerDNMatch            = [Oracle.ManagedDataAccess.Client.OracleConfiguration]::SSLServerDNMatch
    }
}
