function Get-OracleProfileStorePath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProfileStorePath
    )

    if ($ProfileStorePath) {
        return $ProfileStorePath
    }

    if ($script:PSOracleTools.ProfileStorePath) {
        return $script:PSOracleTools.ProfileStorePath
    }

    return (Get-OracleDefaultStoreConfiguration).ProfileStorePath
}
