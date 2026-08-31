function Import-OracleAssembly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DllPath
    )

    if (-not (Test-Path -Path $DllPath -PathType Leaf)) {
        throw "Oracle managed driver DLL not found: $DllPath"
    }

    $requestedPath = [System.IO.Path]::GetFullPath($DllPath)
    $requestedAssemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($requestedPath)
    $loadedAssembly = Get-OracleLoadedAssembly

    if ($loadedAssembly) {
        $loadedAssemblyName = $loadedAssembly.GetName()
        $loadedPath = [string]$loadedAssembly.Location

        if ($loadedAssemblyName.FullName -ne $requestedAssemblyName.FullName) {
            throw ("Oracle.ManagedDataAccess [{0}] is already loaded from [{1}], but [{2}] contains [{3}]. Start a fresh PowerShell process before loading this module version." -f $loadedAssemblyName.Version, $loadedPath, $requestedPath, $requestedAssemblyName.Version)
        }

        if ([string]::IsNullOrWhiteSpace($loadedPath) -or -not (Test-Path -LiteralPath $loadedPath -PathType Leaf)) {
            throw "Oracle.ManagedDataAccess is already loaded without a verifiable file location. Start a fresh PowerShell process before loading this module version."
        }

        $loadedPath = [System.IO.Path]::GetFullPath($loadedPath)
        if ($loadedPath -ne $requestedPath -and (Get-OracleFileSha256 -Path $loadedPath) -ne (Get-OracleFileSha256 -Path $requestedPath)) {
            throw ("Oracle.ManagedDataAccess [{0}] is already loaded from [{1}], but the requested driver at [{2}] has different file contents. Start a fresh PowerShell process before loading this module version." -f $loadedAssemblyName.Version, $loadedPath, $requestedPath)
        }

        $effectivePath = $loadedPath
    }
    else {
        $libPath = Split-Path -Path $requestedPath -Parent
        $script:PSOracleTools.LibPath = $libPath
        Register-OracleAssemblyResolver -LibPath $libPath

        try {
            [System.Reflection.Assembly]::LoadFrom($requestedPath) | Out-Null
        }
        catch [System.Reflection.ReflectionTypeLoadException] {
            $loaderMessages = $_.Exception.LoaderExceptions |
                Where-Object { $_ } |
                ForEach-Object { $_.Message }

            $details = if ($loaderMessages) {
                $loaderMessages -join '; '
            }
            else {
                $_.Exception.Message
            }

            $diagnostics = Get-OracleAssemblyDiagnostics -DllPath $requestedPath -LibPath $libPath
            $summary = Format-OracleAssemblyDiagnosticsSummary -Diagnostics $diagnostics

            throw "Failed to load Oracle managed driver from [$requestedPath]. $details`n$summary"
        }
        catch {
            $diagnostics = Get-OracleAssemblyDiagnostics -DllPath $requestedPath -LibPath $libPath
            $summary = Format-OracleAssemblyDiagnosticsSummary -Diagnostics $diagnostics

            throw "Failed to load Oracle managed driver from [$requestedPath]. $(Get-OracleExceptionMessage -Exception $_.Exception)`n$summary"
        }

        $loadedAssembly = Get-OracleLoadedAssembly
        $effectivePath = if ($loadedAssembly -and $loadedAssembly.Location) {
            [System.IO.Path]::GetFullPath($loadedAssembly.Location)
        }
        else {
            $requestedPath
        }
    }

    $script:PSOracleTools.LibPath = Split-Path -Path $effectivePath -Parent
    Register-OracleAssemblyResolver -LibPath $script:PSOracleTools.LibPath
    $script:PSOracleTools.OracleDllPath = $effectivePath
    $script:PSOracleTools.OracleLoaded  = Test-OracleAssemblyLoaded

    if (-not $script:PSOracleTools.OracleLoaded) {
        throw "Oracle managed driver did not remain loaded after initialization: $requestedPath"
    }

    return $effectivePath
}
