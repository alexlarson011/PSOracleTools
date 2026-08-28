$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path -Path $repoRoot -ChildPath 'PSOracleTools.psd1'

Import-Module $manifestPath -Force
$module = Get-Module PSOracleTools

Describe 'PSOracleTools public contract' {
    It 'exports the documented commands' {
        $expected = @(
            'Initialize-OracleClient', 'New-OracleConnectionString', 'Test-OracleConnection',
            'Set-OracleCredential', 'Get-OracleCredential', 'Remove-OracleCredential',
            'Get-OracleModuleConfiguration', 'Set-OracleModuleConfiguration',
            'Set-OracleConnectionProfile', 'Get-OracleConnectionProfile', 'Remove-OracleConnectionProfile',
            'Invoke-OracleQuery', 'Invoke-OracleScalar', 'Invoke-OracleNonQuery', 'Invoke-OracleSqlFile',
            'Invoke-OraclePlSql', 'Invoke-OracleProcedure', 'Export-OracleDelimitedFile',
            'Export-OracleCsv', 'Export-OracleExcel', 'New-OracleParameter'
        )

        @($module.ExportedFunctions.Keys | Sort-Object) | Should Be @($expected | Sort-Object)
    }

    It 'escapes connection-string values through the Oracle builder' {
        $connectionString = New-OracleConnectionString -DataSource 'db;one' -UserId 'user=one' -Password 'pa;ss'
        $builder = New-Object Oracle.ManagedDataAccess.Client.OracleConnectionStringBuilder($connectionString)

        $builder['Data Source'] | Should Be 'db;one'
        $builder['User Id'] | Should Be 'user=one'
        $builder['Password'] | Should Be 'pa;ss'
    }

    It 'exposes a bounded-row option for exploratory queries' {
        (Get-Command Invoke-OracleQuery).Parameters.ContainsKey('MaxRows') | Should Be $true
    }
}

Describe 'PSOracleTools SQL parsing' {
    It 'keeps semicolons in quoted text and separates SQL statements' {
        $statements = @(& $module {
                Split-OracleScriptStatements -Text "select 'a;b' as value from dual;`nselect 2 from dual;"
            })

        $statements.Count | Should Be 2
        $statements[0].Text | Should Be "select 'a;b' as value from dual"
        $statements[1].Text | Should Be 'select 2 from dual'
    }

    It 'identifies DDL after leading comments' {
        $isDdl = & $module { Test-OracleDdlStatement -StatementText "/* deployment */`ncreate table example_table (id number)" }
        $isDdl | Should Be $true
    }
}

Describe 'PSOracleTools write safeguards' {
    It 'does not open a connection for Invoke-OracleNonQuery -WhatIf' {
        { Invoke-OracleNonQuery -ConnectionString 'User Id=x;Password=x;Data Source=not-a-real-service' -Sql 'delete from example_table' -WhatIf } | Should Not Throw
    }

    It 'does not open a connection for Invoke-OraclePlSql -WhatIf' {
        { Invoke-OraclePlSql -ConnectionString 'User Id=x;Password=x;Data Source=not-a-real-service' -PlSql 'begin null; end;' -WhatIf } | Should Not Throw
    }

    It 'does not execute a parsed SQL file for -WhatIf' {
        $path = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $path -Value 'select * from dual;'
            { Invoke-OracleSqlFile -ConnectionString 'User Id=x;Password=x;Data Source=not-a-real-service' -Path $path -WhatIf } | Should Not Throw
        }
        finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'previews parsed SQL without requiring connection arguments' {
        $path = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $path -Value "create table example_table (id number);`nselect * from dual;"
            $preview = Invoke-OracleSqlFile -Path $path -Preview

            $preview.Preview | Should Be $true
            $preview.StatementCount | Should Be 2
            $preview.Statements[0].IsDdl | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not create a profile store for Set-OracleConnectionProfile -WhatIf' {
        $directory = Join-Path ([System.IO.Path]::GetTempPath()) ('PSOracleTools-Test-' + [guid]::NewGuid().ToString('N'))
        $path = Join-Path $directory 'profiles.json'
        try {
            Set-OracleConnectionProfile -Name 'NoWrite' -DataSource 'example' -CredentialName 'example' -ProfileStorePath $path -WhatIf
            (Test-Path -LiteralPath $path) | Should Be $false
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
