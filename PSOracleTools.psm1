Set-StrictMode -Version Latest

$script:PSOracleTools = @{
    ModuleRoot                 = $PSScriptRoot
    LibPath                    = Join-Path -Path $PSScriptRoot -ChildPath 'lib'
    OracleDllPath              = $null
    OracleLoaded               = $false
    CredentialStore            = $null
    CredentialStorePath        = $null
    ProfileStorePath           = $null
    AssemblyResolver           = $null
    AssemblyResolverRegistered = $false
}

$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$publicPath  = Join-Path -Path $PSScriptRoot -ChildPath 'Public'

Get-ChildItem -Path $privatePath -Filter '*.ps1' -File |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Path $publicPath -Filter '*.ps1' -File |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

$script:PSOracleTools.LibPath = Get-OracleBundledLibPath -ModuleRoot $PSScriptRoot

Initialize-OracleStoreConfiguration | Out-Null
Initialize-OracleClient | Out-Null

Export-ModuleMember -Function @(
    'Initialize-OracleClient',
    'Get-OracleServerInfo',
    'Get-OracleRowCount',
    'Get-OracleTableInfo',
    'Get-OracleObject',
    'Get-OracleInvalidObject',
    'Get-OracleObjectDdl',
    'New-OracleConnectionString',
    'Test-OracleConnection',
    'Test-OracleObject',
    'Wait-OracleConnection',
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
    'Invoke-OracleProcedure',
    'Export-OracleDelimitedFile',
    'Export-OracleCsv',
    'Export-OracleExcel',
    'New-OracleParameter'
)
