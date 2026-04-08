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
        [int]$ConnectionTimeout = 15
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $connection = $null
    $command = $null
    $userName = $null
    $targetDataSource = $null

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
            $resolvedCredential = Resolve-OracleCredential -CredentialName $CredentialName
            $userName = $resolvedCredential.UserName
            $targetDataSource = $CredentialDataSource
            $cs = New-OracleConnectionString -DataSource $CredentialDataSource -UserId $resolvedCredential.UserName -Password ($resolvedCredential.GetNetworkCredential().Password) -ConnectionTimeout $ConnectionTimeout
        }

        $connection = New-OracleConnection -ConnectionString $cs
        Open-OracleConnection -Connection $connection | Out-Null

        $command = New-OracleCommand -Connection $connection -CommandText 'select sysdate from dual'
        $result = $command.ExecuteScalar()

        $sw.Stop()

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

        [pscustomobject]@{
            Success      = $false
            UserName     = $userName
            DataSource   = $targetDataSource
            ErrorMessage = Get-OracleExceptionMessage -Exception $_.Exception
            ElapsedMs    = $sw.ElapsedMilliseconds
        }
    }
    finally {
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}
