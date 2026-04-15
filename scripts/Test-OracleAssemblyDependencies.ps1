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
