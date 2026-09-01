@{
    RootModule        = 'PSOracleTools.psm1'
    ModuleVersion     = '1.1.1'
    GUID              = 'b7d4d8a2-2a4a-4a67-a7f6-6f3e70b0d0c1'
    Author            = 'Alex Larson'
    CompanyName       = 'Personal'
    Copyright         = '(c) Alex Larson. All rights reserved.'
    Description       = 'PowerShell tools for Oracle using Oracle.ManagedDataAccess.dll'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
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

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Oracle', 'ODP.NET', 'PowerShell', 'Database', 'Export')
            LicenseUri = 'https://github.com/alexlarson011/PSOracleTools/blob/main/LICENSE'
            ProjectUri = 'https://github.com/alexlarson011/PSOracleTools'
            ReleaseNotes = 'Version 1.1.1 adds module-wide help, schema discovery, object DDL and metadata tools, row counts, connection waiting, and fixes for SQL parsing, duplicate columns, exports, driver conflicts, inherited settings, and confirmation behavior.'
        }
    }
}
