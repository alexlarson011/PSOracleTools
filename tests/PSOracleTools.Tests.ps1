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

    It 'reports the Oracle assembly that is actually loaded' {
        $initialization = Initialize-OracleClient
        $loadedAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.GetName().Name -eq 'Oracle.ManagedDataAccess' } |
            Select-Object -First 1

        Assert-Equal -Actual ([System.IO.Path]::GetFullPath($initialization.DllPath)) -Expected ([System.IO.Path]::GetFullPath($loadedAssembly.Location))
    }

    It 'rejects different driver contents after Oracle.ManagedDataAccess is loaded' {
        $initialization = Initialize-OracleClient
        $directory = Join-Path ([System.IO.Path]::GetTempPath()) ('PSOracleTools-Test-' + [guid]::NewGuid().ToString('N'))
        $copyPath = Join-Path $directory 'Oracle.ManagedDataAccess.dll'
        try {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath $initialization.DllPath -Destination $copyPath
            $stream = [System.IO.File]::Open($copyPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $stream.WriteByte(0)
            }
            finally {
                $stream.Dispose()
            }

            $threw = $false
            try {
                Initialize-OracleClient -DllPath $copyPath | Out-Null
            }
            catch {
                $threw = $_.Exception.Message -like '*different file contents*Start a fresh PowerShell process*'
            }

            Assert-True -Condition $threw
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'PSOracleTools result conversion' {
    It 'preserves values from duplicate and blank result-column names' {
        $reader = [pscustomobject]@{
            FieldCount = 4
            Position   = -1
            Names      = @('VALUE', 'value', 'VALUE_2', '')
            Values     = @(1, 2, 3, 4)
        }
        $reader | Add-Member -MemberType ScriptMethod -Name Read -Value {
            $this.Position++
            return $this.Position -eq 0
        }
        $reader | Add-Member -MemberType ScriptMethod -Name GetName -Value { param($index) return $this.Names[$index] }
        $reader | Add-Member -MemberType ScriptMethod -Name IsDBNull -Value { param($index) return $false }
        $reader | Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($index) return $this.Values[$index] }

        $rows = @($script:module.Invoke({ param($dataReader) ConvertFrom-OracleDataReader -Reader $dataReader }, $reader))

        Assert-Equal -Actual $rows.Count -Expected 1
        Assert-SequenceEqual -Actual @($rows[0].PSObject.Properties.Name) -Expected @('VALUE', 'value_2', 'VALUE_2_2', 'Column4')
        Assert-SequenceEqual -Actual @($rows[0].PSObject.Properties.Value) -Expected @(1, 2, 3, 4)
    }

    It 'preserves a complete one-column name' {
        $reader = [pscustomobject]@{ FieldCount = 1; Position = -1 }
        $reader | Add-Member -MemberType ScriptMethod -Name Read -Value {
            $this.Position++
            return $this.Position -eq 0
        }
        $reader | Add-Member -MemberType ScriptMethod -Name GetName -Value { return 'MOVIE_COUNT' }
        $reader | Add-Member -MemberType ScriptMethod -Name IsDBNull -Value { return $false }
        $reader | Add-Member -MemberType ScriptMethod -Name GetValue -Value { return 12 }

        $rows = @($script:module.Invoke({ param($dataReader) ConvertFrom-OracleDataReader -Reader $dataReader }, $reader))

        Assert-SequenceEqual -Actual @($rows[0].PSObject.Properties.Name) -Expected @('MOVIE_COUNT')
        Assert-Equal -Actual $rows[0].MOVIE_COUNT -Expected 12
    }
}

Describe 'PSOracleTools wrapper defaults' {
    It 'allows CSV exports to inherit a profile command timeout' {
        Mock -CommandName Export-OracleDelimitedFile -ModuleName PSOracleTools -MockWith {
            [pscustomobject]@{ Operation = 'Export-OracleDelimitedFile' }
        }

        Export-OracleCsv -ProfileName 'Example' -Sql 'select 1 from dual' -Path 'example.csv' | Out-Null

        Should -Invoke -CommandName Export-OracleDelimitedFile -ModuleName PSOracleTools -Times 1 -Exactly -ParameterFilter {
            -not $PSBoundParameters.ContainsKey('CommandTimeout')
        }
    }

    It 'forwards explicit CSV command timeouts' {
        Mock -CommandName Export-OracleDelimitedFile -ModuleName PSOracleTools -MockWith {
            [pscustomobject]@{ Operation = 'Export-OracleDelimitedFile' }
        }

        Export-OracleCsv -ProfileName 'Example' -Sql 'select 1 from dual' -Path 'example.csv' -CommandTimeout 42 | Out-Null

        Should -Invoke -CommandName Export-OracleDelimitedFile -ModuleName PSOracleTools -Times 1 -Exactly -ParameterFilter {
            $CommandTimeout -eq 42
        }
    }

    It 'allows procedures to inherit profile defaults' {
        $global:PSOracleToolsProcedureInvocationParameters = $null
        Mock -CommandName Invoke-OraclePlSql -ModuleName PSOracleTools -MockWith {
            $global:PSOracleToolsProcedureInvocationParameters = @{} + $PSBoundParameters
            [pscustomobject]@{ Operation = 'Invoke-OraclePlSql' }
        }

        try {
            Invoke-OracleProcedure -ProfileName 'Example' -Procedure 'example_package.run' -Confirm:$false | Out-Null

            Should -Invoke -CommandName Invoke-OraclePlSql -ModuleName PSOracleTools -Times 1 -Exactly
            Assert-False -Condition $global:PSOracleToolsProcedureInvocationParameters.ContainsKey('CommandTimeout')
            Assert-False -Condition $global:PSOracleToolsProcedureInvocationParameters.ContainsKey('LogSql')
        }
        finally {
            Remove-Variable -Name PSOracleToolsProcedureInvocationParameters -Scope Global -ErrorAction SilentlyContinue
        }
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

    It 'keeps apostrophes and semicolons inside Oracle alternative-quoted text' {
        $literals = @(
            "q'[Alex's; movie]'"
            "Q'{brace's; value}'"
            "q'(parenthesis's; value)'"
            "q'<angle's; value>'"
            "q'!custom's; value!'"
            "q''single's; delimiter''"
            "nq'~national's; value~'"
            "q'[first's;`nsecond line]'"
        )

        foreach ($literal in $literals) {
            $sql = "select $literal as value from dual;`nselect 2 from dual;"
            $statements = @($script:module.Invoke({
                        param($text)
                        Split-OracleScriptStatements -Text $text
                    }, $sql))

            Assert-Equal -Actual $statements.Count -Expected 2
            Assert-Equal -Actual $statements[0].Text -Expected "select $literal as value from dual"
            Assert-Equal -Actual $statements[1].Text -Expected 'select 2 from dual'
        }
    }

    It 'identifies DDL after leading comments' {
        $isDdl = $script:module.Invoke({ Test-OracleDdlStatement -StatementText "/* deployment */`ncreate table example_table (id number)" })
        Assert-True -Condition $isDdl
    }
}

Describe 'PSOracleTools write safeguards' {
    It 'replaces only completed output files and honors NoClobber' {
        $directory = Join-Path ([System.IO.Path]::GetTempPath()) ('PSOracleTools-Test-' + [guid]::NewGuid().ToString('N'))
        $targetPath = Join-Path $directory 'output.csv'
        $tempPath = Join-Path $directory 'completed.tmp'
        $blockedTempPath = Join-Path $directory 'blocked.tmp'
        try {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllText($targetPath, 'previous')
            [System.IO.File]::WriteAllText($tempPath, 'completed')

            $script:module.Invoke({ param($temp, $target) Complete-OracleOutputFile -TempPath $temp -Path $target }, $tempPath, $targetPath) | Out-Null
            Assert-Equal -Actual ([System.IO.File]::ReadAllText($targetPath)) -Expected 'completed'
            Assert-False -Condition (Test-Path -LiteralPath $tempPath)

            [System.IO.File]::WriteAllText($blockedTempPath, 'blocked')
            $threw = $false
            try {
                $script:module.Invoke({ param($temp, $target) Complete-OracleOutputFile -TempPath $temp -Path $target -NoClobber }, $blockedTempPath, $targetPath) | Out-Null
            }
            catch {
                $threw = $true
            }

            Assert-True -Condition $threw
            Assert-Equal -Actual ([System.IO.File]::ReadAllText($targetPath)) -Expected 'completed'
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

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
