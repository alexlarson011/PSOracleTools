function Get-OracleProfileStorePath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProfileStorePath
    )

    if ($ProfileStorePath) {
        return $ProfileStorePath
    }

    if ($env:PSORACLETOOLS_PROFILE_STORE) {
        return $env:PSORACLETOOLS_PROFILE_STORE
    }

    $root = Get-OracleToolsRoot
    return (Join-Path -Path $root -ChildPath 'profiles.json')
}
