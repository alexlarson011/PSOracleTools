<#
.SYNOPSIS
Reports Oracle managed driver dependency diagnostics.

.DESCRIPTION
Inspects the bundled Oracle.ManagedDataAccess assembly and related dependencies in the module lib folder.
The report shows runtime details, bundled assembly versions, dependency mismatches, and related assemblies already loaded in the current process.
Use -TryModuleImport to attempt importing PSOracleTools after the dependency report.

.PARAMETER DllPath
Optional path to Oracle.ManagedDataAccess.dll. Defaults to the module's bundled DLL.

.PARAMETER TryModuleImport
Attempts to import the module after reporting dependency diagnostics.

.EXAMPLE
.\scripts\Test-OracleAssemblyDependencies.ps1

Displays dependency diagnostics for the bundled Oracle managed driver.

.EXAMPLE
.\scripts\Test-OracleAssemblyDependencies.ps1 -TryModuleImport

Displays dependency diagnostics and then attempts to import the module.
#>
param(
    [Parameter()]
    [string]$DllPath,

    [Parameter()]
    [switch]$TryModuleImport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent

. (Join-Path -Path $repoRoot -ChildPath 'Private\Get-OracleBundledLibPath.ps1')
. (Join-Path -Path $repoRoot -ChildPath 'Private\Get-OracleAssemblyDiagnostics.ps1')

$libPath = Get-OracleBundledLibPath -ModuleRoot $repoRoot

if (-not $DllPath) {
    $DllPath = Get-OracleBundledDllPath -ModuleRoot $repoRoot
}

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
    Write-Host 'No required dependency mismatches detected in bundled assemblies.'
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

    $manifestPath = Join-Path -Path $repoRoot -ChildPath 'PSOracleTools.psd1'

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Write-Warning ("Module manifest not found at [{0}]. The diagnostics script is running, but the module files were not fully deployed." -f $manifestPath)
        return
    }

    try {
        Import-Module $manifestPath -Force -ErrorAction Stop | Out-Null
        Write-Host 'Import succeeded.'
    }
    catch {
        Write-Warning $_.Exception.Message

        $loaderExceptionsProperty = $_.Exception.PSObject.Properties['LoaderExceptions']
        if ($loaderExceptionsProperty -and $loaderExceptionsProperty.Value) {
            $_.Exception.LoaderExceptions |
                Where-Object { $_ } |
                ForEach-Object { Write-Warning $_.Message }
        }
    }
}
