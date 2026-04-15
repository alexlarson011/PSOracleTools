function Import-OracleAssembly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DllPath
    )

    if (-not (Test-Path -Path $DllPath -PathType Leaf)) {
        throw "Oracle managed driver DLL not found: $DllPath"
    }

    $libPath = Split-Path -Path $DllPath -Parent
    $script:PSOracleTools.LibPath = $libPath
    Initialize-OracleAssemblyCatalog -LibPath $libPath
    Register-OracleAssemblyResolver -LibPath $libPath

    if (-not (Test-OracleAssemblyLoaded)) {
        try {
            [System.Reflection.Assembly]::LoadFrom($DllPath) | Out-Null
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

            $diagnostics = Get-OracleAssemblyDiagnostics -DllPath $DllPath -LibPath $libPath
            $summary = Format-OracleAssemblyDiagnosticsSummary -Diagnostics $diagnostics

            throw "Failed to load Oracle managed driver from [$DllPath]. $details`n$summary"
        }
        catch {
            $diagnostics = Get-OracleAssemblyDiagnostics -DllPath $DllPath -LibPath $libPath
            $summary = Format-OracleAssemblyDiagnosticsSummary -Diagnostics $diagnostics

            throw "Failed to load Oracle managed driver from [$DllPath]. $(Get-OracleExceptionMessage -Exception $_.Exception)`n$summary"
        }
    }

    $script:PSOracleTools.OracleDllPath = $DllPath
    $script:PSOracleTools.OracleLoaded  = Test-OracleAssemblyLoaded

    if (-not $script:PSOracleTools.OracleLoaded) {
        throw "Oracle managed driver did not remain loaded after initialization: $DllPath"
    }
}
