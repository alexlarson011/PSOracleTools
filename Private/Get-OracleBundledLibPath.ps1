function Get-OracleBundledLibPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ModuleRoot = $PSScriptRoot.Replace('\Private', '')
    )

    $preferredPath = Join-Path -Path $ModuleRoot -ChildPath 'lib\net472'
    $fallbackPath = Join-Path -Path $ModuleRoot -ChildPath 'lib'

    if (Test-Path -LiteralPath (Join-Path -Path $preferredPath -ChildPath 'Oracle.ManagedDataAccess.dll') -PathType Leaf) {
        return $preferredPath
    }

    return $fallbackPath
}

function Get-OracleBundledDllPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ModuleRoot = $PSScriptRoot.Replace('\Private', '')
    )

    return (Join-Path -Path (Get-OracleBundledLibPath -ModuleRoot $ModuleRoot) -ChildPath 'Oracle.ManagedDataAccess.dll')
}
