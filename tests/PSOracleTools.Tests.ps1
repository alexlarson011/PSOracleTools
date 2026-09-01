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
            'Initialize-OracleClient', 'Get-OracleServerInfo', 'Get-OracleRowCount', 'Get-OracleTableInfo', 'Get-OracleObject',
            'Get-OracleInvalidObject', 'Get-OracleObjectDdl', 'New-OracleConnectionString',
            'Test-OracleConnection', 'Test-OracleObject', 'Wait-OracleConnection',
            'Set-OracleCredential', 'Get-OracleCredential', 'Remove-OracleCredential',
            'Get-OracleModuleConfiguration', 'Set-OracleModuleConfiguration',
            'Set-OracleConnectionProfile', 'Get-OracleConnectionProfile', 'Remove-OracleConnectionProfile',
            'Invoke-OracleQuery', 'Invoke-OracleScalar', 'Invoke-OracleNonQuery', 'Invoke-OracleSqlFile',
            'Invoke-OraclePlSql', 'Invoke-OracleProcedure', 'Export-OracleDelimitedFile',
            'Export-OracleCsv', 'Export-OracleExcel', 'New-OracleParameter'
        )

        Assert-SequenceEqual -Actual @($script:module.ExportedFunctions.Keys | Sort-Object) -Expected @($expected | Sort-Object)
    }

    It 'publishes module-level conceptual help for every exported command' {
        $help = @(Get-Help about_PSOracleTools -ErrorAction Stop)
        $helpPath = Join-Path -Path $script:repoRoot -ChildPath 'en-US\about_PSOracleTools.help.txt'
        $helpText = Get-Content -LiteralPath $helpPath -Raw

        Assert-True -Condition ($help.Count -gt 0)
        Assert-True -Condition (@($help.Name) -contains 'about_PSOracleTools')
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$help[0].Synopsis))

        foreach ($name in @($script:module.ExportedFunctions.Keys)) {
            $pattern = '(?m)^ {{4}}{0}\r?$' -f [regex]::Escape($name)
            Assert-True -Condition ($helpText -match $pattern) -Message "Module-level help does not catalog [$name]."
        }
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

Describe 'PSOracleTools metadata commands' {
    It 'normalizes and safely quotes Oracle identifiers' {
        $ordinary = $script:module.Invoke({ Resolve-OracleIdentifier -Name 'movies' -Description 'Table name' })
        $quoted = $script:module.Invoke({ Resolve-OracleIdentifier -Name '"Mixed Name"' -Description 'Table name' })

        Assert-Equal -Actual $ordinary.Name -Expected 'MOVIES'
        Assert-Equal -Actual $ordinary.Sql -Expected '"MOVIES"'
        Assert-Equal -Actual $quoted.Name -Expected 'Mixed Name'
        Assert-Equal -Actual $quoted.Sql -Expected '"Mixed Name"'

        $threw = $false
        try {
            $script:module.Invoke({ Resolve-OracleIdentifier -Name 'APP.MOVIES' -Description 'Table name' }) | Out-Null
        }
        catch {
            $threw = $true
        }
        Assert-True -Condition $threw
    }

    It 'returns a stable exact row-count result and inherits profile defaults' {
        $global:PSOracleToolsQueryInvocation = $null
        Mock -CommandName Invoke-OracleQuery -ModuleName PSOracleTools -MockWith {
            $global:PSOracleToolsQueryInvocation = [pscustomobject]@{ Sql = $Sql; Parameters = $Parameters }
            [pscustomobject]@{ schema_name = 'APP'; row_count = [decimal]6 }
        }

        try {
            $result = Get-OracleRowCount -ProfileName 'Example' -Table 'movies'

            Assert-Equal -Actual $result.PSObject.TypeNames[0] -Expected 'PSOracleTools.RowCountResult'
            Assert-Equal -Actual $result.Schema -Expected 'APP'
            Assert-Equal -Actual $result.Table -Expected 'MOVIES'
            Assert-Equal -Actual $result.RowCount -Expected ([decimal]6)
            Assert-Equal -Actual $result.CountType -Expected 'Exact'
            Assert-True -Condition $global:PSOracleToolsQueryInvocation.Sql.Contains('from "MOVIES"')
            Should -Invoke -CommandName Invoke-OracleQuery -ModuleName PSOracleTools -Times 1 -Exactly -ParameterFilter {
                -not $PSBoundParameters.ContainsKey('CommandTimeout')
            }
        }
        finally {
            Remove-Variable -Name PSOracleToolsQueryInvocation -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'binds row-count filter values instead of interpolating them' {
        $global:PSOracleToolsQueryInvocation = $null
        Mock -CommandName Invoke-OracleQuery -ModuleName PSOracleTools -MockWith {
            $global:PSOracleToolsQueryInvocation = [pscustomobject]@{ Sql = $Sql; Parameters = $Parameters }
            [pscustomobject]@{ schema_name = 'APP'; row_count = [decimal]4 }
        }

        try {
            Get-OracleRowCount -ConnectionString 'example' -Table 'movies' -Where 'release_year >= :year' -Parameters @{ year = 2000 } | Out-Null

            Assert-True -Condition $global:PSOracleToolsQueryInvocation.Sql.Contains('where release_year >= :year')
            Assert-Equal -Actual $global:PSOracleToolsQueryInvocation.Parameters.year -Expected 2000
            Assert-False -Condition $global:PSOracleToolsQueryInvocation.Sql.Contains('2000')
        }
        finally {
            Remove-Variable -Name PSOracleToolsQueryInvocation -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'distinguishes a successful object lookup from a missing object' {
        Mock -CommandName Invoke-OracleQuery -ModuleName PSOracleTools -MockWith {
            [pscustomobject]@{
                schema_name  = 'APP'
                owner        = $null
                object_name  = $null
                object_type  = $null
                status       = $null
                created      = $null
                last_ddl_time = $null
            }
        }

        $result = Test-OracleObject -ConnectionString 'example' -Name 'missing_table' -ObjectType Table

        Assert-True -Condition $result.Success
        Assert-False -Condition $result.Exists
        Assert-Equal -Actual $result.MatchCount -Expected 0
        Assert-Equal -Actual $result.Schema -Expected 'APP'
    }

    It 'lists schema objects with bound filters and clean defaults' {
        $global:PSOracleToolsObjectInvocation = $null
        Mock -CommandName Invoke-OracleQuery -ModuleName PSOracleTools -MockWith {
            $global:PSOracleToolsObjectInvocation = [pscustomobject]@{ Sql = $Sql; Parameters = $Parameters }
            return @(
                [pscustomobject]@{
                    schema_name = 'APP'; object_name = 'MOVIES'; subobject_name = $null; object_id = [decimal]10
                    data_object_id = [decimal]11; object_type = 'TABLE'; created = [datetime]'2026-01-01'
                    last_ddl_time = [datetime]'2026-01-02'; specification_timestamp = '2026-01-02:00:00:00'
                    status = 'VALID'; temporary = 'N'; generated = 'N'; secondary = 'N'; namespace = [decimal]1
                    edition_name = $null
                }
                [pscustomobject]@{
                    schema_name = 'APP'; object_name = 'MOVIE_PKG'; subobject_name = $null; object_id = [decimal]12
                    data_object_id = $null; object_type = 'PACKAGE BODY'; created = [datetime]'2026-01-01'
                    last_ddl_time = [datetime]'2026-01-03'; specification_timestamp = '2026-01-03:00:00:00'
                    status = 'VALID'; temporary = 'N'; generated = 'N'; secondary = 'N'; namespace = [decimal]2
                    edition_name = 'ORA$BASE'
                }
            )
        }

        try {
            $results = @(Get-OracleObject -ProfileName 'Example' -Schema 'app' -NameLike 'MOVIE%' -ObjectType Table, PackageBody -Status Valid -MaxObjects 5)

            Assert-Equal -Actual $results.Count -Expected 2
            Assert-Equal -Actual $results[0].PSObject.TypeNames[0] -Expected 'PSOracleTools.SchemaObjectResult'
            Assert-SequenceEqual -Actual @($results.ObjectType) -Expected @('TABLE', 'PACKAGE BODY')
            Assert-Equal -Actual $global:PSOracleToolsObjectInvocation.Parameters.schema_name -Expected 'APP'
            Assert-Equal -Actual $global:PSOracleToolsObjectInvocation.Parameters.name_like -Expected 'MOVIE%'
            Assert-True -Condition (@($global:PSOracleToolsObjectInvocation.Parameters.Values) -contains 'TABLE')
            Assert-True -Condition (@($global:PSOracleToolsObjectInvocation.Parameters.Values) -contains 'PACKAGE BODY')
            Assert-True -Condition ($global:PSOracleToolsObjectInvocation.Sql -match "o.generated = 'N'")
            Assert-True -Condition ($global:PSOracleToolsObjectInvocation.Sql -match "o.secondary = 'N'")
            Assert-True -Condition ($global:PSOracleToolsObjectInvocation.Sql -match 'o.subobject_name is null')
            Should -Invoke -CommandName Invoke-OracleQuery -ModuleName PSOracleTools -Times 1 -Exactly -ParameterFilter {
                $MaxRows -eq 5 -and -not $PSBoundParameters.ContainsKey('CommandTimeout')
            }
        }
        finally {
            Remove-Variable -Name PSOracleToolsObjectInvocation -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'groups table columns, primary keys, and index columns' {
        Mock -CommandName Invoke-OracleQuery -ModuleName PSOracleTools -MockWith {
            if ($Sql -match 'from all_tables') {
                return [pscustomobject]@{
                    schema_name = 'APP'; table_name = 'MOVIES'; tablespace_name = 'USERS'; temporary = 'N'
                    partitioned = 'NO'; iot_type = $null; compression = 'DISABLED'; compress_for = $null
                    num_rows = [decimal]6; blocks = [decimal]1; avg_row_len = [decimal]20; last_analyzed = [datetime]'2026-01-01'
                }
            }
            if ($Sql -match 'from all_tab_columns') {
                return @(
                    [pscustomobject]@{
                        column_id = 1; column_name = 'MOVIE_ID'; data_type = 'NUMBER'; data_length = 22
                        char_length = 0; char_used = $null; data_precision = 10; data_scale = 0; nullable = 'N'
                        data_default = $null; primary_key_name = 'PK_MOVIES'; primary_key_position = 1
                    }
                    [pscustomobject]@{
                        column_id = 2; column_name = 'MOVIE_NM'; data_type = 'VARCHAR2'; data_length = 100
                        char_length = 100; char_used = 'B'; data_precision = $null; data_scale = $null; nullable = 'Y'
                        data_default = $null; primary_key_name = $null; primary_key_position = $null
                    }
                )
            }
            if ($Sql -match 'from all_indexes') {
                return @(
                    [pscustomobject]@{
                        index_owner = 'APP'; index_name = 'PK_MOVIES'; index_type = 'NORMAL'; uniqueness = 'UNIQUE'
                        compression = 'DISABLED'; prefix_length = $null; tablespace_name = 'USERS'; status = 'VALID'
                        partitioned = 'NO'; last_analyzed = [datetime]'2026-01-01'; column_name = 'MOVIE_ID'
                        column_position = 1; column_length = 22; descend = 'ASC'
                    }
                )
            }
        }

        $result = Get-OracleTableInfo -ConnectionString 'example' -Table 'movies'

        Assert-Equal -Actual $result.PSObject.TypeNames[0] -Expected 'PSOracleTools.TableInfoResult'
        Assert-Equal -Actual $result.ColumnCount -Expected 2
        Assert-SequenceEqual -Actual @($result.Columns.Name) -Expected @('MOVIE_ID', 'MOVIE_NM')
        Assert-Equal -Actual $result.PrimaryKey.Name -Expected 'PK_MOVIES'
        Assert-SequenceEqual -Actual @($result.PrimaryKey.Columns) -Expected @('MOVIE_ID')
        Assert-Equal -Actual $result.IndexCount -Expected 1
        Assert-SequenceEqual -Actual @($result.Indexes[0].Columns.Name) -Expected @('MOVIE_ID')
    }

    It 'maps friendly DDL object types to DBMS_METADATA names' {
        $global:PSOracleToolsDdlInvocation = $null
        Mock -CommandName Invoke-OracleQuery -ModuleName PSOracleTools -MockWith {
            $global:PSOracleToolsDdlInvocation = [pscustomobject]@{ Sql = $Sql; Parameters = $Parameters }
            [pscustomobject]@{ schema_name = 'APP'; ddl = 'create package body MOVIE_PKG as end;' }
        }

        try {
            $result = Get-OracleObjectDdl -ConnectionString 'example' -Name 'movie_pkg' -ObjectType PackageBody

            Assert-Equal -Actual $result.MetadataType -Expected 'PACKAGE_BODY'
            Assert-Equal -Actual $global:PSOracleToolsDdlInvocation.Parameters.metadata_type -Expected 'PACKAGE_BODY'
            Assert-True -Condition $result.Ddl.StartsWith('create package body')
        }
        finally {
            Remove-Variable -Name PSOracleToolsDdlInvocation -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'returns stable invalid-object rows with error counts' {
        $global:PSOracleToolsInvalidObjectSql = $null
        Mock -CommandName Invoke-OracleQuery -ModuleName PSOracleTools -MockWith {
            $global:PSOracleToolsInvalidObjectSql = $Sql
            [pscustomobject]@{
                schema_name = 'APP'; object_name = 'MOVIE_PKG'; object_type = 'PACKAGE BODY'; status = 'INVALID'
                error_count = [decimal]2; created = [datetime]'2026-01-01'; last_ddl_time = [datetime]'2026-01-02'
            }
        }

        try {
            $result = Get-OracleInvalidObject -ConnectionString 'example' -ObjectType PackageBody

            Assert-Equal -Actual $result.PSObject.TypeNames[0] -Expected 'PSOracleTools.InvalidObjectResult'
            Assert-Equal -Actual $result.Name -Expected 'MOVIE_PKG'
            Assert-Equal -Actual $result.ErrorCount -Expected 2
            Assert-True -Condition ($global:PSOracleToolsInvalidObjectSql -match 'from all_objects o\s+where')
        }
        finally {
            Remove-Variable -Name PSOracleToolsInvalidObjectSql -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'waits through transient connection failures' {
        $global:PSOracleToolsConnectionAttempts = 0
        Mock -CommandName Test-OracleConnection -ModuleName PSOracleTools -MockWith {
            $global:PSOracleToolsConnectionAttempts++
            if ($global:PSOracleToolsConnectionAttempts -eq 1) {
                return [pscustomobject]@{ Success = $false; DataSource = 'example'; ErrorMessage = 'not ready' }
            }
            return [pscustomobject]@{
                Success = $true; DataSource = 'example'; UserName = 'APP'; ServerVersion = '19c'; DatabaseTime = Get-Date
            }
        }
        Mock -CommandName Start-Sleep -ModuleName PSOracleTools

        try {
            $result = Wait-OracleConnection -ConnectionString 'example' -TimeoutSeconds 5 -RetryIntervalSeconds 0.1

            Assert-True -Condition $result.Success
            Assert-Equal -Actual $result.Attempts -Expected 2
            Assert-False -Condition $result.TimedOut
            Should -Invoke -CommandName Start-Sleep -ModuleName PSOracleTools -Times 1 -Exactly
        }
        finally {
            Remove-Variable -Name PSOracleToolsConnectionAttempts -Scope Global -ErrorAction SilentlyContinue
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
