Describe 'PSOracleTools' {
BeforeAll {
    $script:repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:manifestPath = Join-Path -Path $script:repoRoot -ChildPath 'PSOracleTools.psd1'

    Import-Module $script:manifestPath -Force
    $script:module = Get-Module PSOracleTools

    function script:Assert-Equal {
        param($Actual, $Expected, [string]$Message = 'Values are not equal.')

        if (-not [object]::Equals($Actual, $Expected)) {
            throw ('{0} Expected [{1}], actual [{2}].' -f $Message, $Expected, $Actual)
        }
    }

    function script:Assert-SequenceEqual {
        param($Actual, $Expected, [string]$Message = 'Sequences are not equal.')

        $actualItems = @($Actual)
        $expectedItems = @($Expected)

        if ($actualItems.Count -ne $expectedItems.Count) {
            throw ('{0} Expected count [{1}], actual count [{2}].' -f $Message, $expectedItems.Count, $actualItems.Count)
        }

        for ($i = 0; $i -lt $expectedItems.Count; $i++) {
            if (-not [object]::Equals($actualItems[$i], $expectedItems[$i])) {
                throw ('{0} Difference at index [{1}]. Expected [{2}], actual [{3}].' -f $Message, $i, $expectedItems[$i], $actualItems[$i])
            }
        }
    }

    function script:Assert-True {
        param([bool]$Condition, [string]$Message = 'Expected condition to be true.')

        if (-not $Condition) {
            throw $Message
        }
    }

    function script:Assert-False {
        param([bool]$Condition, [string]$Message = 'Expected condition to be false.')

        if ($Condition) {
            throw $Message
        }
    }

    function script:Assert-NotThrow {
        param([scriptblock]$ScriptBlock, [string]$Message = 'Expected script block not to throw.')

        try {
            & $ScriptBlock
        }
        catch {
            throw ('{0} Error: {1}' -f $Message, $_.Exception.Message)
        }
    }
}

Describe 'PSOracleTools public contract' {
    It 'exports the documented commands' {
        $expected = @(
            'Initialize-OracleClient', 'Get-OracleServerInfo', 'New-OracleConnectionString', 'Test-OracleConnection',
            'Set-OracleCredential', 'Get-OracleCredential', 'Remove-OracleCredential',
            'Get-OracleModuleConfiguration', 'Set-OracleModuleConfiguration',
            'Set-OracleConnectionProfile', 'Get-OracleConnectionProfile', 'Remove-OracleConnectionProfile',
            'Invoke-OracleQuery', 'Invoke-OracleScalar', 'Invoke-OracleNonQuery', 'Invoke-OracleSqlFile',
            'Invoke-OraclePlSql', 'Invoke-OracleProcedure', 'Export-OracleDelimitedFile',
            'Export-OracleCsv', 'Export-OracleExcel', 'New-OracleParameter'
        )

        Assert-SequenceEqual -Actual @($script:module.ExportedFunctions.Keys | Sort-Object) -Expected @($expected | Sort-Object)
    }

    It 'escapes connection-string values through the Oracle builder' {
        $connectionString = New-OracleConnectionString -DataSource 'db;one' -UserId 'user=one' -Password 'pa;ss'
        $builder = New-Object Oracle.ManagedDataAccess.Client.OracleConnectionStringBuilder($connectionString)

        Assert-Equal -Actual $builder['Data Source'] -Expected 'db;one'
        Assert-Equal -Actual $builder['User Id'] -Expected 'user=one'
        Assert-Equal -Actual $builder['Password'] -Expected 'pa;ss'
    }

    It 'exposes a bounded-row option for exploratory queries' {
        Assert-True -Condition (Get-Command Invoke-OracleQuery).Parameters.ContainsKey('MaxRows')
    }
}

Describe 'PSOracleTools SQL parsing' {
    It 'keeps semicolons in quoted text and separates SQL statements' {
        $statements = @($script:module.Invoke({
                Split-OracleScriptStatements -Text "select 'a;b' as value from dual;`nselect 2 from dual;"
            }))

        Assert-Equal -Actual $statements.Count -Expected 2
        Assert-Equal -Actual $statements[0].Text -Expected "select 'a;b' as value from dual"
        Assert-Equal -Actual $statements[1].Text -Expected 'select 2 from dual'
    }

    It 'identifies DDL after leading comments' {
        $isDdl = $script:module.Invoke({ Test-OracleDdlStatement -StatementText "/* deployment */`ncreate table example_table (id number)" })
        Assert-True -Condition $isDdl
    }
}

Describe 'PSOracleTools write safeguards' {
    It 'does not open a connection for Invoke-OracleNonQuery -WhatIf' {
        Assert-NotThrow -ScriptBlock { Invoke-OracleNonQuery -ConnectionString 'User Id=x;Password=x;Data Source=not-a-real-service' -Sql 'delete from example_table' -WhatIf }
    }

    It 'does not open a connection for Invoke-OraclePlSql -WhatIf' {
        Assert-NotThrow -ScriptBlock { Invoke-OraclePlSql -ConnectionString 'User Id=x;Password=x;Data Source=not-a-real-service' -PlSql 'begin null; end;' -WhatIf }
    }

    It 'does not open a connection for Invoke-OracleProcedure -WhatIf' {
        Assert-NotThrow -ScriptBlock { Invoke-OracleProcedure -ConnectionString 'User Id=x;Password=x;Data Source=not-a-real-service' -Procedure 'example_package.example_procedure' -WhatIf }
    }

    It 'does not execute a parsed SQL file for -WhatIf' {
        $path = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $path -Value 'select * from dual;'
            Assert-NotThrow -ScriptBlock { Invoke-OracleSqlFile -ConnectionString 'User Id=x;Password=x;Data Source=not-a-real-service' -Path $path -WhatIf }
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

            Assert-True -Condition $preview.Preview
            Assert-Equal -Actual $preview.StatementCount -Expected 2
            Assert-True -Condition $preview.Statements[0].IsDdl
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
            Assert-False -Condition (Test-Path -LiteralPath $path)
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not create a credential store for Set-OracleCredential -WhatIf' {
        $directory = Join-Path ([System.IO.Path]::GetTempPath()) ('PSOracleTools-Test-' + [guid]::NewGuid().ToString('N'))
        $path = Join-Path $directory 'credentials.json'
        $password = ConvertTo-SecureString -String 'not-a-real-password' -AsPlainText -Force
        $credential = New-Object PSCredential('example', $password)
        try {
            Set-OracleCredential -Name 'NoWrite' -Credential $credential -CredentialStorePath $path -WhatIf
            Assert-False -Condition (Test-Path -LiteralPath $path)
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes profile changes without a default confirmation prompt' {
        $directory = Join-Path ([System.IO.Path]::GetTempPath()) ('PSOracleTools-Test-' + [guid]::NewGuid().ToString('N'))
        $path = Join-Path $directory 'profiles.json'
        $originalConfirmPreference = $ConfirmPreference
        try {
            $ConfirmPreference = 'High'
            Set-OracleConnectionProfile -Name 'NoPrompt' -DataSource 'example' -CredentialName 'example' -ProfileStorePath $path | Out-Null
            Assert-True -Condition (Test-Path -LiteralPath $path)
        }
        finally {
            $ConfirmPreference = $originalConfirmPreference
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves repeated profile updates in valid JSON' {
        $directory = Join-Path ([System.IO.Path]::GetTempPath()) ('PSOracleTools-Test-' + [guid]::NewGuid().ToString('N'))
        $path = Join-Path $directory 'profiles.json'
        try {
            Set-OracleConnectionProfile -Name 'ConcurrentOne' -DataSource 'ConcurrentOne' -CredentialName 'ConcurrentOne' -ProfileStorePath $path -Confirm:$false | Out-Null
            Set-OracleConnectionProfile -Name 'ConcurrentTwo' -DataSource 'ConcurrentTwo' -CredentialName 'ConcurrentTwo' -ProfileStorePath $path -Confirm:$false | Out-Null
            $names = @(Get-OracleConnectionProfile -ProfileStorePath $path | Select-Object -ExpandProperty Name | Sort-Object)
            Assert-SequenceEqual -Actual $names -Expected @('ConcurrentOne', 'ConcurrentTwo')
            Assert-NotThrow -ScriptBlock { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Out-Null }
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'waits for an exclusive profile-store lock rather than overwriting it' {
        $directory = Join-Path ([System.IO.Path]::GetTempPath()) ('PSOracleTools-Test-' + [guid]::NewGuid().ToString('N'))
        $path = Join-Path $directory 'profiles.json'
        $lockPath = "$path.lock"
        try {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
            New-Item -Path $lockPath -ItemType File -Force | Out-Null

            $threw = $false
            try {
                $script:module.Invoke({ param($StorePath) Update-OracleNamedRecordStore -Path $StorePath -StoreDescription 'connection profile' -LockTimeoutSeconds 1 -Update { param($records) return $records } }, $path)
            }
            catch {
                $threw = $true
            }

            Assert-True -Condition $threw
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
}
