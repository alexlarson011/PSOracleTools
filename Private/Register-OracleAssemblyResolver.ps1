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

        $requestedName = (New-Object System.Reflection.AssemblyName($resolveEventArgs.Name)).Name

        $loadedAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.GetName().Name -eq $requestedName } |
            Select-Object -First 1

        if ($loadedAssembly) {
            return $loadedAssembly
        }

        $candidatePath = Join-Path -Path $script:PSOracleTools.LibPath -ChildPath "$requestedName.dll"

        if (Test-Path -Path $candidatePath -PathType Leaf) {
            return [System.Reflection.Assembly]::LoadFrom($candidatePath)
        }

        return $null
    }

    [AppDomain]::CurrentDomain.add_AssemblyResolve($script:PSOracleTools.AssemblyResolver)
    $script:PSOracleTools.AssemblyResolverRegistered = $true
}
