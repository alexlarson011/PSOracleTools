function Test-OracleAssemblyLoaded {
    [CmdletBinding()]
    param()

    $assembly = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Oracle.ManagedDataAccess' } |
        Select-Object -First 1

    return [bool]$assembly
}