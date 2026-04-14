param(
    [Parameter()]
    [string]$DllPath,

    [Parameter()]
    [switch]$TryModuleImport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$libPath = Join-Path -Path $repoRoot -ChildPath 'lib'

if (-not $DllPath) {
    $DllPath = Join-Path -Path $libPath -ChildPath 'Oracle.ManagedDataAccess.dll'
}

. (Join-Path -Path $repoRoot -ChildPath 'Private\Get-OracleAssemblyDiagnostics.ps1')

$diagnostics = Get-OracleAssemblyDiagnostics -DllPath $DllPath -LibPath $libPath

Write-Host 'Runtime'
$diagnostics.Runtime | Format-List

Write-Host ''
Write-Host 'Bundled Assemblies'
$diagnostics.BundledAssemblies |
    Select-Object Name, VersionText, FileVersion, PublicKeyToken, Path |
    Format-Table -AutoSize

Write-Host ''
Write-Host 'Dependency Issues'
if ($diagnostics.Issues.Count -gt 0) {
    $diagnostics.Issues |
        Select-Object AssemblyName, ReferenceName, ReferenceVersionText, CandidateSource, CandidateVersionText, Status, CandidatePath |
        Format-Table -AutoSize
}
else {
    Write-Host 'No dependency mismatches detected in bundled assemblies.'
}

Write-Host ''
Write-Host 'Loaded Assemblies'
if ($diagnostics.LoadedAssemblies.Count -gt 0) {
    $diagnostics.LoadedAssemblies |
        Select-Object Name, VersionText, Location |
        Format-Table -AutoSize
}
else {
    Write-Host 'No related assemblies are currently loaded.'
}

if ($TryModuleImport) {
    Write-Host ''
    Write-Host 'Module Import'

    try {
        Import-Module (Join-Path -Path $repoRoot -ChildPath 'PSOracleTools.psd1') -Force -ErrorAction Stop | Out-Null
        Write-Host 'Import succeeded.'
    }
    catch {
        Write-Warning $_.Exception.Message

        if ($_.Exception.LoaderExceptions) {
            $_.Exception.LoaderExceptions |
                Where-Object { $_ } |
                ForEach-Object { Write-Warning $_.Message }
        }
    }
}
