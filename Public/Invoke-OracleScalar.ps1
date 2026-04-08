function Invoke-OracleScalar {
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
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleScalar started; DataSource={0}; CommandTimeout={1}" -f $targetDataSource, $CommandTimeout)
            if ($LogSql) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OracleScalar SQL: {0}" -f $Sql)
            }
            if ($LogParameters) {
                Write-OracleLog -Path $LogPath -Message ("Invoke-OracleScalar Parameters: {0}" -f ((Get-OracleParameterSummary -Parameters $Parameters) -join ', '))
            }
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText $Sql -CommandTimeout $CommandTimeout
        Add-OracleParameters -Command $command -Parameters $Parameters

        $result = $command.ExecuteScalar()
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Invoke-OracleScalar succeeded; DataSource={0}; Result={1}" -f $connection.DataSource, $result)
        }
        return $result
    }
    catch {
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Invoke-OracleScalar failed; DataSource={0}; Error={1}" -f $targetDataSource, (Get-OracleExceptionMessage -Exception $_.Exception))
        }
        throw
    }
    finally {
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
