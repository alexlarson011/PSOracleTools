@{
    RootModule        = 'PSOracleTools.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b7d4d8a2-2a4a-4a67-a7f6-6f3e70b0d0c1'
    Author            = 'Alex Larson'
    CompanyName       = 'Personal'
    Copyright         = '(c) Alex Larson. All rights reserved.'
    Description       = 'PowerShell tools for Oracle using Oracle.ManagedDataAccess.dll'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
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

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Oracle', 'ODP.NET', 'PowerShell', 'Database', 'Export')
            LicenseUri = 'https://github.com/alexlarson011/PSOracleTools/blob/main/LICENSE'
            ProjectUri = 'https://github.com/alexlarson011/PSOracleTools'
            ReleaseNotes = 'Version 1.0.0 adds connection profiles, SecretManagement-backed credentials, SQL file transactions, typed operational result objects, improved exports, optional Excel template automation, positional helper parameters, and expanded validation and help coverage.'
        }
    }
}
