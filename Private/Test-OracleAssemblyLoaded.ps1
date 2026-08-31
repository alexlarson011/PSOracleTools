function Get-OracleLoadedAssembly {
    [CmdletBinding()]
    param()

    return [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Oracle.ManagedDataAccess' } |
        Select-Object -First 1
}

function Test-OracleAssemblyLoaded {
    [CmdletBinding()]
    param()

    return [bool](Get-OracleLoadedAssembly)
}
