function Get-OracleCredentialStorePath {
    [CmdletBinding()]
    param()

    $root = Get-OracleToolsRoot
    return (Join-Path -Path $root -ChildPath 'credentials.json')
}