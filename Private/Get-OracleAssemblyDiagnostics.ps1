function Get-OracleAssemblyDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DllPath,

        [Parameter(Mandatory)]
        [string]$LibPath
    )

    $frameworkAssemblyNames = @(
        'mscorlib',
        'netstandard',
        'System',
        'System.Configuration',
        'System.Core',
        'System.Data',
        'System.DirectoryServices.Protocols',
        'System.Drawing',
        'System.EnterpriseServices',
        'System.Net.Http',
        'System.Numerics',
        'System.Security',
        'System.Transactions',
        'System.Web',
        'System.Xml',
        'System.Xml.Linq'
    )

    function Get-OracleAssemblyIdentity {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        try {
            $assemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($Path)
            $publicKeyToken = [System.BitConverter]::ToString($assemblyName.GetPublicKeyToken()).Replace('-', '').ToLowerInvariant()

            [pscustomobject]@{
                Name             = $assemblyName.Name
                Version          = $assemblyName.Version
                VersionText      = $assemblyName.Version.ToString()
                PublicKeyToken   = $publicKeyToken
                Path             = $Path
                FileVersion      = (Get-Item -LiteralPath $Path).VersionInfo.FileVersion
                IdentityLoadable = $true
                Error            = $null
            }
        }
        catch {
            [pscustomobject]@{
                Name             = [System.IO.Path]::GetFileNameWithoutExtension($Path)
                Version          = $null
                VersionText      = $null
                PublicKeyToken   = $null
                Path             = $Path
                FileVersion      = $null
                IdentityLoadable = $false
                Error            = $_.Exception.Message
            }
        }
    }

    function Get-OracleAssemblyReferences {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        try {
            $assembly = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($Path)
            $owner = $assembly.GetName().Name

            foreach ($reference in $assembly.GetReferencedAssemblies()) {
                [pscustomobject]@{
                    AssemblyName       = $owner
                    ReferenceName      = $reference.Name
                    ReferenceVersion   = $reference.Version
                    ReferenceVersionText = $reference.Version.ToString()
                    PublicKeyToken     = [System.BitConverter]::ToString($reference.GetPublicKeyToken()).Replace('-', '').ToLowerInvariant()
                }
            }
        }
        catch {
            [pscustomobject]@{
                AssemblyName         = [System.IO.Path]::GetFileNameWithoutExtension($Path)
                ReferenceName        = $null
                ReferenceVersion     = $null
                ReferenceVersionText = $null
                PublicKeyToken       = $null
                Error                = $_.Exception.Message
            }
        }
    }

    $runtime = [pscustomobject]@{
        PSVersion            = $PSVersionTable.PSVersion.ToString()
        PSEdition            = $PSVersionTable.PSEdition
        FrameworkDescription = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
        CLRVersion           = [System.Environment]::Version.ToString()
        ProcessBitness       = if ([System.Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' }
        OSVersion            = [System.Environment]::OSVersion.VersionString
    }

    $bundledAssemblies = @(
        Get-ChildItem -Path $LibPath -Filter '*.dll' -File -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object { Get-OracleAssemblyIdentity -Path $_.FullName }
    )

    $bundledByName = @{}
    foreach ($assembly in $bundledAssemblies | Where-Object { $_.Name }) {
        $bundledByName[$assembly.Name] = $assembly
    }

    $interestingNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $bundledByName.Keys) {
        [void]$interestingNames.Add($name)
    }

    $referenceStatus = @()
    foreach ($assembly in $bundledAssemblies | Where-Object { $_.IdentityLoadable }) {
        foreach ($reference in @(Get-OracleAssemblyReferences -Path $assembly.Path)) {
            if (-not $reference.ReferenceName) {
                continue
            }

            [void]$interestingNames.Add($reference.ReferenceName)

            $bundledMatch = $null
            if ($bundledByName.ContainsKey($reference.ReferenceName)) {
                $bundledMatch = $bundledByName[$reference.ReferenceName]
            }

            $loadedMatches = @(
                [AppDomain]::CurrentDomain.GetAssemblies() |
                    Where-Object { $_.GetName().Name -eq $reference.ReferenceName } |
                    Sort-Object { $_.GetName().Version } -Descending
            )

            $loadedVersion = $null
            $loadedLocation = $null
            if ($loadedMatches.Count -gt 0) {
                $loadedVersion = $loadedMatches[0].GetName().Version
                $loadedLocation = $loadedMatches[0].Location
            }

            $status = 'Framework'
            $candidateVersion = $null
            $candidateSource = $null
            $candidatePath = $null

            if ($bundledMatch) {
                $candidateVersion = $bundledMatch.Version
                $candidateSource = 'Bundled'
                $candidatePath = $bundledMatch.Path

                if ($reference.ReferenceVersion -eq $bundledMatch.Version) {
                    $status = 'BundledExact'
                }
                elseif ($reference.ReferenceVersion -lt $bundledMatch.Version) {
                    $status = 'BundledHigherVersion'
                }
                else {
                    $status = 'BundledLowerVersion'
                }
            }
            elseif ($loadedVersion) {
                $candidateVersion = $loadedVersion
                $candidateSource = 'Loaded'
                $candidatePath = $loadedLocation

                if ($reference.ReferenceVersion -eq $loadedVersion) {
                    $status = 'LoadedExact'
                }
                elseif ($reference.ReferenceVersion -lt $loadedVersion) {
                    $status = 'LoadedHigherVersion'
                }
                else {
                    $status = 'LoadedLowerVersion'
                }
            }
            elseif ($reference.ReferenceName -notin $frameworkAssemblyNames) {
                $status = 'Missing'
            }

            $referenceStatus += [pscustomobject]@{
                AssemblyName          = $reference.AssemblyName
                ReferenceName         = $reference.ReferenceName
                ReferenceVersion      = $reference.ReferenceVersion
                ReferenceVersionText  = $reference.ReferenceVersionText
                CandidateVersion      = $candidateVersion
                CandidateVersionText  = if ($candidateVersion) { $candidateVersion.ToString() } else { $null }
                CandidateSource       = $candidateSource
                CandidatePath         = $candidatePath
                Status                = $status
                PublicKeyToken        = $reference.PublicKeyToken
            }
        }
    }

    $loadedAssemblies = @(
        [AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $interestingNames.Contains($_.GetName().Name) } |
            Sort-Object { $_.GetName().Name } |
            ForEach-Object {
                $name = $_.GetName()
                [pscustomobject]@{
                    Name       = $name.Name
                    Version    = $name.Version
                    VersionText = $name.Version.ToString()
                    Location   = $_.Location
                }
            }
    )

    $issues = @(
        $referenceStatus |
            Where-Object {
                $_.Status -in @('Missing', 'BundledLowerVersion', 'LoadedLowerVersion')
            } |
            Sort-Object AssemblyName, ReferenceName
    )

    [pscustomobject]@{
        DllPath            = $DllPath
        LibPath            = $LibPath
        Runtime            = $runtime
        BundledAssemblies  = $bundledAssemblies
        LoadedAssemblies   = $loadedAssemblies
        ReferenceStatus    = $referenceStatus
        Issues             = $issues
    }
}

function Format-OracleAssemblyDiagnosticsSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Diagnostics
    )

    $runtime = $Diagnostics.Runtime
    $runtimeLine = 'Runtime: PowerShell {0} ({1}), {2}, CLR {3}, {4}' -f `
        $runtime.PSVersion, `
        $runtime.PSEdition, `
        $runtime.FrameworkDescription, `
        $runtime.CLRVersion, `
        $runtime.ProcessBitness

    $bundledLine = 'Bundled assemblies: {0}' -f (
        @(
            $Diagnostics.BundledAssemblies |
                Where-Object { $_.VersionText } |
                ForEach-Object { '{0} {1}' -f $_.Name, $_.VersionText }
        ) -join '; '
    )

    $issueLines = @(
        $Diagnostics.Issues |
            Select-Object -First 12 |
            ForEach-Object {
                if ($_.CandidateVersionText) {
                    '{0} -> {1}: requested {2}, {3} has {4}' -f `
                        $_.AssemblyName, `
                        $_.ReferenceName, `
                        $_.ReferenceVersionText, `
                        $_.CandidateSource.ToLowerInvariant(), `
                        $_.CandidateVersionText
                }
                else {
                    '{0} -> {1}: requested {2}, no bundled or preloaded match found' -f `
                        $_.AssemblyName, `
                        $_.ReferenceName, `
                        $_.ReferenceVersionText
                }
            }
    )

    if ($Diagnostics.Issues.Count -gt $issueLines.Count) {
        $issueLines += '{0} additional issue(s) omitted' -f ($Diagnostics.Issues.Count - $issueLines.Count)
    }

    if ($issueLines.Count -eq 0) {
        $issueLines = 'No dependency mismatches detected in the bundled assembly set.'
    }

    return @(
        $runtimeLine
        $bundledLine
        'Dependency issues:'
        ($issueLines -join [Environment]::NewLine)
    ) -join [Environment]::NewLine
}
