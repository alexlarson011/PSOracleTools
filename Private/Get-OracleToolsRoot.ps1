function Get-OracleToolsRoot {
    [CmdletBinding()]
    param()

    $root = Join-Path -Path $env:APPDATA -ChildPath 'PSOracleTools'

    if (-not (Test-Path -Path $root)) {
        New-Item -Path $root -ItemType Directory -Force | Out-Null
    }

    return $root
}