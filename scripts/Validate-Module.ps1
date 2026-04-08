Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path -Path $repoRoot -ChildPath 'PSOracleTools.psd1'

Write-Host 'Validating manifest...'
$manifest = Test-ModuleManifest -Path $manifestPath

Write-Host 'Importing module...'
$module = Import-Module $manifestPath -Force -PassThru

$expectedFunctions = @(
    'Initialize-OracleClient',
    'New-OracleConnectionString',
    'Test-OracleConnection',
    'Set-OracleCredential',
    'Get-OracleCredential',
    'Remove-OracleCredential',
    'Set-OracleConnectionProfile',
    'Get-OracleConnectionProfile',
    'Remove-OracleConnectionProfile',
    'Invoke-OracleQuery',
    'Invoke-OracleScalar',
    'Invoke-OracleNonQuery',
    'Invoke-OracleSqlFile',
    'Invoke-OraclePlSql',
    'Export-OracleDelimitedFile',
    'Export-OracleCsv',
    'New-OracleParameter'
)

Write-Host 'Checking exported commands...'
$exported = @($module.ExportedFunctions.Keys | Sort-Object)
$missing = @($expectedFunctions | Where-Object { $_ -notin $exported })

if ($missing.Count -gt 0) {
    throw ('Missing exported functions: {0}' -f ($missing -join ', '))
}

Write-Host 'Checking help discovery...'
$helpTargets = @(
    'Test-OracleConnection',
    'Invoke-OracleQuery',
    'Invoke-OracleSqlFile',
    'Export-OracleCsv'
)

foreach ($name in $helpTargets) {
    $help = Get-Help $name -ErrorAction Stop
    if (-not $help.Synopsis) {
        throw "Help synopsis missing for [$name]."
    }
}

Write-Host 'Validation succeeded.'
