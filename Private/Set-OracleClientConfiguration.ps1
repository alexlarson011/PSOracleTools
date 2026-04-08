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

    [Oracle.ManagedDataAccess.Client.OracleConfiguration]::SSLServerDNMatch = $true

    [pscustomobject]@{
        TnsAdmin       = [Oracle.ManagedDataAccess.Client.OracleConfiguration]::TnsAdmin
        WalletLocation = [Oracle.ManagedDataAccess.Client.OracleConfiguration]::WalletLocation
        SSLServerDNMatch = [Oracle.ManagedDataAccess.Client.OracleConfiguration]::SSLServerDNMatch
    }
}
