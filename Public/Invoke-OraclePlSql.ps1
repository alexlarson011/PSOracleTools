function Invoke-OraclePlSql {
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
        [string]$PlSql,

        [Parameter()]
        $Parameters,

        [Parameter()]
        [int]$CommandTimeout = 300,

        [Parameter()]
        [string]$CredentialStorePath,

        [Parameter()]
        [switch]$Log,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [switch]$LogSql,

        [Parameter()]
        [switch]$LogParameters
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $connection = $null
    $command = $null
    $targetDataSource = $null

    try {
        switch ($PSCmdlet.ParameterSetName) {
            'ByConnectionString' {
                $cs = $ConnectionString
            }
            'ByCredential' {
                $targetDataSource = $DataSource
                $cs = New-OracleConnectionString -DataSource $DataSource -UserId $Credential.UserName -Password ($Credential.GetNetworkCredential().Password)
            }
            'ByCredentialName' {
                $resolvedCredential = Resolve-OracleCredential -CredentialName $CredentialName -CredentialStorePath $CredentialStorePath
                $targetDataSource = $CredentialDataSource
                $cs = New-OracleConnectionString -DataSource $CredentialDataSource -UserId $resolvedCredential.UserName -Password ($resolvedCredential.GetNetworkCredential().Password)
            }
        }

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OraclePlSql started; DataSource={0}; CommandTimeout={1}" -f $targetDataSource, $CommandTimeout)
            if ($LogSql) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OraclePlSql Block: {0}" -f $PlSql)
            }
            if ($LogParameters) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OraclePlSql Parameters: {0}" -f ((Get-OracleParameterSummary -Parameters $Parameters) -join ', '))
            }
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText $PlSql -CommandTimeout $CommandTimeout
        Add-OracleParameters -Command $command -Parameters $Parameters

        [void]$command.ExecuteNonQuery()
        $sw.Stop()

        $outputParameters = @{}
        foreach ($param in $command.Parameters) {
            if ($param.Direction -ne [System.Data.ParameterDirection]::Input) {
                $outputParameters[$param.ParameterName] = if ($param.Value -eq [DBNull]::Value) { $null } else { $param.Value }
            }
        }

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OraclePlSql succeeded; DataSource={0}; OutputParameterCount={1}; ElapsedMs={2}" -f $connection.DataSource, $outputParameters.Count, $sw.ElapsedMilliseconds)
        }

        [pscustomobject]@{
            Success          = $true
            ElapsedMs        = $sw.ElapsedMilliseconds
            OutputParameters = $outputParameters
        }
    }
    catch {
        $sw.Stop()
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Invoke-OraclePlSql failed; DataSource={0}; ElapsedMs={1}; Error={2}" -f $targetDataSource, $sw.ElapsedMilliseconds, (Get-OracleExceptionMessage -Exception $_.Exception))
        }
        throw
    }
    finally {
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
