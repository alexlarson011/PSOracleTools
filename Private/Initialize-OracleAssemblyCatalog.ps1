function Initialize-OracleAssemblyCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LibPath
    )

    $byFullName = @{}
    $byName = @{}

    Get-ChildItem -Path $LibPath -Filter '*.dll' -File -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $assemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($_.FullName)
            }
            catch {
                return
            }

            $entry = [pscustomobject]@{
                Name        = $assemblyName.Name
                FullName    = $assemblyName.FullName
                Version     = $assemblyName.Version
                VersionText = $assemblyName.Version.ToString()
                Path        = $_.FullName
            }

            $byFullName[$entry.FullName] = $entry.Path

            if (-not $byName.ContainsKey($entry.Name)) {
                $byName[$entry.Name] = New-Object System.Collections.ArrayList
            }

            [void]$byName[$entry.Name].Add($entry)
        }

    $script:PSOracleTools.AssemblyCatalogByFullName = $byFullName
    $script:PSOracleTools.AssemblyCatalogByName = $byName
}

function Find-OracleAssemblyPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Reflection.AssemblyName]$RequestedAssemblyName
    )

    if (-not $script:PSOracleTools.AssemblyCatalogByFullName -or -not $script:PSOracleTools.AssemblyCatalogByName) {
        Initialize-OracleAssemblyCatalog -LibPath $script:PSOracleTools.LibPath
    }

    if ($script:PSOracleTools.AssemblyCatalogByFullName.ContainsKey($RequestedAssemblyName.FullName)) {
        return $script:PSOracleTools.AssemblyCatalogByFullName[$RequestedAssemblyName.FullName]
    }

    if (-not $script:PSOracleTools.AssemblyCatalogByName.ContainsKey($RequestedAssemblyName.Name)) {
        return $null
    }

    $candidates = @($script:PSOracleTools.AssemblyCatalogByName[$RequestedAssemblyName.Name])
    $exactVersionMatch = @(
        $candidates |
            Where-Object { $_.Version -eq $RequestedAssemblyName.Version } |
            Select-Object -First 1
    )

    if ($exactVersionMatch.Count -gt 0) {
        return $exactVersionMatch[0].Path
    }

    if (-not $RequestedAssemblyName.Version -and $candidates.Count -eq 1) {
        return $candidates[0].Path
    }

    return $null
}
