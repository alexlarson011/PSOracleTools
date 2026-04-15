function Register-OracleAssemblyResolver {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LibPath
    )

    if ($script:PSOracleTools.AssemblyResolverRegistered) {
        return
    }

    $script:PSOracleTools.AssemblyResolver = [System.ResolveEventHandler]{
        param($sender, $resolveEventArgs)

        $requestedAssemblyName = New-Object System.Reflection.AssemblyName($resolveEventArgs.Name)
        $requestedName = $requestedAssemblyName.Name

        $loadedAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.GetName().Name -eq $requestedName } |
            Select-Object -First 1

        if ($loadedAssembly) {
            return $loadedAssembly
        }

        $candidatePath = Join-Path -Path $script:PSOracleTools.LibPath -ChildPath "$requestedName.dll"

        if (-not (Test-Path -Path $candidatePath -PathType Leaf)) {
            return $null
        }

        $resolveKey = '{0}|{1}' -f $requestedAssemblyName.FullName, $candidatePath
        if (-not $script:PSOracleTools.AssemblyResolveInProgress.Add($resolveKey)) {
            return $null
        }

        try {
            return [System.Reflection.Assembly]::LoadFrom($candidatePath)
        }
        finally {
            [void]$script:PSOracleTools.AssemblyResolveInProgress.Remove($resolveKey)
        }
    }

    [AppDomain]::CurrentDomain.add_AssemblyResolve($script:PSOracleTools.AssemblyResolver)
    $script:PSOracleTools.AssemblyResolverRegistered = $true
}
