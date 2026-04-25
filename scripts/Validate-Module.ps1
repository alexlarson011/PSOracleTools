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
    'Get-OracleModuleConfiguration',
    'Set-OracleModuleConfiguration',
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
    'Export-OracleExcel',
    'New-OracleParameter'
)

Write-Host 'Checking exported commands...'
$exported = @($module.ExportedFunctions.Keys | Sort-Object)
$missing = @($expectedFunctions | Where-Object { $_ -notin $exported })
$unexpected = @($exported | Where-Object { $_ -notin $expectedFunctions })

if ($missing.Count -gt 0) {
    throw ('Missing exported functions: {0}' -f ($missing -join ', '))
}

if ($unexpected.Count -gt 0) {
    throw ('Unexpected exported functions: {0}' -f ($unexpected -join ', '))
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

Write-Host 'Checking connection string escaping...'
$connectionString = New-OracleConnectionString -DataSource 'db;one' -UserId 'user=one' -Password 'pa;ss'
$connectionStringBuilder = New-Object Oracle.ManagedDataAccess.Client.OracleConnectionStringBuilder($connectionString)
if ($connectionStringBuilder['Data Source'] -ne 'db;one' -or
    $connectionStringBuilder['User Id'] -ne 'user=one' -or
    $connectionStringBuilder['Password'] -ne 'pa;ss') {
    throw 'Connection string escaping validation failed.'
}

Write-Host 'Checking SQL script parser directives...'
$parsedStatements = @(& $module {
        param([string]$SqlText)
        Split-OracleScriptStatements -Text $SqlText
    } "prompt hello`nselect * from dual;")

if ($parsedStatements.Count -ne 1 -or $parsedStatements[0].Text -ne 'select * from dual') {
    throw 'SQL script parser directive validation failed.'
}

Write-Host 'Checking SQL transaction DDL detection...'
$ddlDetection = & $module {
    [pscustomobject]@{
        SelectIsDdl = Test-OracleDdlStatement -StatementText 'select * from dual'
        CreateIsDdl = Test-OracleDdlStatement -StatementText "/* comment */`ncreate table t (id number)"
    }
}

if ($ddlDetection.SelectIsDdl -or -not $ddlDetection.CreateIsDdl) {
    throw 'SQL transaction DDL detection validation failed.'
}

Write-Host 'Validation succeeded.'
