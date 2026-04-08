function Test-OracleConnection {
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

        [Parameter()]
        [int]$ConnectionTimeout = 15,

        [Parameter()]
        [string]$CredentialStorePath,

        [Parameter()]
        [switch]$Log,

        [Parameter()]
        [string]$LogPath
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $connection = $null
    $command = $null
    $userName = $null
    $targetDataSource = $null
    $operationSucceeded = $false

    try {
        if ($PSCmdlet.ParameterSetName -eq 'ByConnectionString') {
            $cs = $ConnectionString
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByCredential') {
            $userName = $Credential.UserName
            $targetDataSource = $DataSource
            $cs = New-OracleConnectionString -DataSource $DataSource -UserId $Credential.UserName -Password ($Credential.GetNetworkCredential().Password) -ConnectionTimeout $ConnectionTimeout
        }
        else {
            $resolvedCredential = Resolve-OracleCredential -CredentialName $CredentialName -CredentialStorePath $CredentialStorePath
            $userName = $resolvedCredential.UserName
            $targetDataSource = $CredentialDataSource
            $cs = New-OracleConnectionString -DataSource $CredentialDataSource -UserId $resolvedCredential.UserName -Password ($resolvedCredential.GetNetworkCredential().Password) -ConnectionTimeout $ConnectionTimeout
        }

        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Message ("Test-OracleConnection started; DataSource={0}; UserName={1}; ConnectionTimeout={2}" -f $targetDataSource, $userName, $ConnectionTimeout)
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText 'select sysdate from dual'
        $result = $command.ExecuteScalar()

        $sw.Stop()
        $operationSucceeded = $true

        [pscustomobject]@{
            Success       = $true
            UserName      = $userName
            DataSource    = $connection.DataSource
            ServerVersion = $connection.ServerVersion
            DatabaseTime  = $result
            ElapsedMs     = $sw.ElapsedMilliseconds
        }
    }
    catch {
        $sw.Stop()
        if ($Log -or $LogPath) {
            Write-OracleLog -Path $LogPath -Level ERROR -Message ("Test-OracleConnection failed; DataSource={0}; UserName={1}; ElapsedMs={2}; Error={3}" -f $targetDataSource, $userName, $sw.ElapsedMilliseconds, (Get-OracleExceptionMessage -Exception $_.Exception))
        }

        [pscustomobject]@{
            Success      = $false
            UserName     = $userName
            DataSource   = $targetDataSource
            ErrorMessage = Get-OracleExceptionMessage -Exception $_.Exception
            ElapsedMs    = $sw.ElapsedMilliseconds
        }
    }
    finally {
        if (($Log -or $LogPath) -and $operationSucceeded) {
            Write-OracleLog -Path $LogPath -Message ("Test-OracleConnection succeeded; DataSource={0}; UserName={1}; ElapsedMs={2}" -f $connection.DataSource, $userName, $sw.ElapsedMilliseconds)
        }

        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
