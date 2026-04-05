function Import-OracleAssembly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DllPath
    )

    if (-not (Test-Path -Path $DllPath -PathType Leaf)) {
        throw "Oracle managed driver DLL not found: $DllPath"
    }

    if (-not (Test-OracleAssemblyLoaded)) {
        Add-Type -Path $DllPath
    }

    $script:PSOracleTools.OracleDllPath = $DllPath
    $script:PSOracleTools.OracleLoaded  = $true
}