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
    Register-OracleAssemblyResolver -LibPath $libPath

    if (-not (Test-OracleAssemblyLoaded)) {
        try {
            Get-ChildItem -Path $libPath -Filter '*.dll' -File |
                Where-Object { $_.Name -ne (Split-Path -Path $DllPath -Leaf) } |
                Sort-Object Name |
                ForEach-Object {
                    $assemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($_.FullName)
                    $alreadyLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
                        Where-Object { $_.GetName().Name -eq $assemblyName.Name } |
                        Select-Object -First 1

                    if (-not $alreadyLoaded) {
                        [System.Reflection.Assembly]::LoadFrom($_.FullName) | Out-Null
                    }
                }

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

            throw "Failed to load Oracle managed driver from [$DllPath]. $details"
        }
        catch {
            throw "Failed to load Oracle managed driver from [$DllPath]. $(Get-OracleExceptionMessage -Exception $_.Exception)"
        }
    }

    $script:PSOracleTools.OracleDllPath = $DllPath
    $script:PSOracleTools.OracleLoaded  = Test-OracleAssemblyLoaded

    if (-not $script:PSOracleTools.OracleLoaded) {
        throw "Oracle managed driver did not remain loaded after initialization: $DllPath"
    }
}
