function Export-OracleDelimitedFile {
    [CmdletBinding(DefaultParameterSetName = 'ByConnectionString')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByConnectionString')]
        [string]$ConnectionString,

        [Parameter(Mandatory, ParameterSetName = 'ByCredential')]
        [PSCredential]$Credential,

        [Parameter(Mandatory, ParameterSetName = 'ByCredential')]
        [string]$DataSource,

        [Parameter(Mandatory, ParameterSetName = 'ByCredentialName')]
        [string]$CredentialName,

        [Parameter(Mandatory, ParameterSetName = 'ByCredentialName')]
        [string]$CredentialDataSource,

        [Parameter(Mandatory)]
        [string]$Sql,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$Delimiter = '|',

        [Parameter()]
        [switch]$IncludeHeader,

        [Parameter()]
        [string]$NullValue = '',

        [Parameter()]
        [switch]$QuoteAll,

        [Parameter()]
        $Parameters,

        [Parameter()]
        [int]$CommandTimeout = 300
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $connection = $null
    $command = $null
    $reader = $null
    $writer = $null
    $rowCount = 0

    try {
        switch ($PSCmdlet.ParameterSetName) {
            'ByConnectionString' {
                $cs = $ConnectionString
            }
            'ByCredential' {
                $cs = New-OracleConnectionString -DataSource $DataSource -UserId $Credential.UserName -Password ($Credential.GetNetworkCredential().Password)
            }
            'ByCredentialName' {
                $resolvedCredential = Resolve-OracleCredential -CredentialName $CredentialName
                $cs = New-OracleConnectionString -DataSource $CredentialDataSource -UserId $resolvedCredential.UserName -Password ($resolvedCredential.GetNetworkCredential().Password)
            }
        }

        $directory = Split-Path -Path $Path -Parent
        if ($directory -and -not (Test-Path -Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText $Sql -CommandTimeout $CommandTimeout
        Add-OracleParameters -Command $command -Parameters $Parameters

        $reader = $command.ExecuteReader()
        $writer = New-Object System.IO.StreamWriter($Path, $false, [System.Text.Encoding]::UTF8)

        if ($IncludeHeader) {
            $header = for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                ConvertTo-DelimitedValue -Value $reader.GetName($i) -Delimiter $Delimiter -NullValue $NullValue -QuoteAll:$QuoteAll
            }
            $writer.WriteLine(($header -join $Delimiter))
        }

        while ($reader.Read()) {
            $line = for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $value = if ($reader.IsDBNull($i)) { $null } else { $reader.GetValue($i) }
                ConvertTo-DelimitedValue -Value $value -Delimiter $Delimiter -NullValue $NullValue -QuoteAll:$QuoteAll
            }

            $writer.WriteLine(($line -join $Delimiter))
            $rowCount++
        }

        $sw.Stop()

        [pscustomobject]@{
            Success   = $true
            Path      = $Path
            RowCount  = $rowCount
            ElapsedMs = $sw.ElapsedMilliseconds
        }
    }
    finally {
        if ($writer) { $writer.Flush() }
        Close-OracleResource -Object $writer
        Close-OracleResource -Object $reader
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}