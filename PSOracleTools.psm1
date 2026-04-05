Set-StrictMode -Version Latest

$script:PSOracleTools = @{
    ModuleRoot      = $PSScriptRoot
    OracleDllPath   = $null
    OracleLoaded    = $false
    CredentialStore = $null
}

$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$publicPath  = Join-Path -Path $PSScriptRoot -ChildPath 'Public'

Get-ChildItem -Path $privatePath -Filter '*.ps1' -File |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Path $publicPath -Filter '*.ps1' -File |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function @(
    'Initialize-OracleClient',
    'New-OracleConnectionString',
    'Test-OracleConnection',
    'Set-OracleCredential',
    'Get-OracleCredential',
    'Remove-OracleCredential',
    'Invoke-OracleQuery',
    'Invoke-OracleScalar',
    'Invoke-OracleNonQuery',
    'Invoke-OraclePlSql',
    'Export-OracleDelimitedFile',
    'New-OracleParameter'
)