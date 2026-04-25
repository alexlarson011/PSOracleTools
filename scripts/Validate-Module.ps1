<#
.SYNOPSIS
Runs lightweight validation for the PSOracleTools module.

.DESCRIPTION
Validates the module manifest, imports the module, checks the exported command surface, verifies comment-help discovery and parameter coverage, and runs focused regression checks for connection string escaping, positional helper commands, SQL script parsing, and transaction DDL detection.

.EXAMPLE
.\scripts\Validate-Module.ps1

Runs the repository-local validation pass.
#>
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

Write-Host 'Checking help parameter coverage...'
$helpScriptPaths = @(
    Get-ChildItem -Path (Join-Path -Path $repoRoot -ChildPath 'Public') -Filter '*.ps1'
    Get-ChildItem -Path (Join-Path -Path $repoRoot -ChildPath 'Optional') -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue
    Get-ChildItem -Path (Join-Path -Path $repoRoot -ChildPath 'scripts') -Filter '*.ps1' -Recurse
)

foreach ($scriptPath in $helpScriptPaths) {
    $scriptText = Get-Content -LiteralPath $scriptPath.FullName -Raw
    if ($scriptText -notmatch '(?s)^\s*<#.*?\.SYNOPSIS.*?#>') {
        throw "Comment-based help is missing for [$($scriptPath.FullName)]."
    }

    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Unable to parse [$($scriptPath.FullName)] while checking help coverage: $($parseErrors[0].Message)"
    }

    $functionAst = $scriptAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $paramBlock = if ($functionAst) { $functionAst.Body.ParamBlock } else { $scriptAst.ParamBlock }
    $actualParameters = if ($paramBlock) {
        @($paramBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath } | Sort-Object -Unique)
    }
    else {
        @()
    }

    $documentedParameters = @(
        [regex]::Matches($scriptText, '(?m)^\.PARAMETER\s+(\w+)') |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique
    )

    $undocumentedParameters = @($actualParameters | Where-Object { $_ -notin $documentedParameters })
    $unknownParameters = @($documentedParameters | Where-Object { $_ -notin $actualParameters })

    if ($undocumentedParameters.Count -gt 0) {
        throw "Help is missing parameter(s) for [$($scriptPath.FullName)]: $($undocumentedParameters -join ', ')"
    }

    if ($unknownParameters.Count -gt 0) {
        throw "Help documents unknown parameter(s) for [$($scriptPath.FullName)]: $($unknownParameters -join ', ')"
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

Write-Host 'Checking positional helper commands...'
$positionalConnectionString = New-OracleConnectionString 'db;two' 'user=two' 'pw;two'
$positionalConnectionStringBuilder = New-Object Oracle.ManagedDataAccess.Client.OracleConnectionStringBuilder($positionalConnectionString)
if ($positionalConnectionStringBuilder['Data Source'] -ne 'db;two' -or
    $positionalConnectionStringBuilder['User Id'] -ne 'user=two' -or
    $positionalConnectionStringBuilder['Password'] -ne 'pw;two') {
    throw 'Positional connection string validation failed.'
}

$positionalParameter = New-OracleParameter movie_id 1 Int32
if ($positionalParameter.ParameterName -ne 'movie_id' -or
    $positionalParameter.Value -ne 1 -or
    $positionalParameter.OracleDbType -ne [Oracle.ManagedDataAccess.Client.OracleDbType]::Int32) {
    throw 'Positional parameter validation failed.'
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
