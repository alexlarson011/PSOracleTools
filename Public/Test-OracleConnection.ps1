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
        [string]$DataSource2
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $connection = $null
    $command = $null

    try {
        if ($PSCmdlet.ParameterSetName -eq 'ByConnectionString') {
            $cs = $ConnectionString
            $userName = $null
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByCredential') {
            $userName = $Credential.UserName
            $cs = New-OracleConnectionString -DataSource $DataSource -UserId $Credential.UserName -Password ($Credential.GetNetworkCredential().Password)
        }
        else {
            $resolvedCredential = Resolve-OracleCredential -CredentialName $CredentialName
            $userName = $resolvedCredential.UserName
            $cs = New-OracleConnectionString -DataSource $DataSource2 -UserId $resolvedCredential.UserName -Password ($resolvedCredential.GetNetworkCredential().Password)
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
            DataSource   = $DataSource
            ErrorMessage = $_.Exception.Message
            ElapsedMs    = $sw.ElapsedMilliseconds
        }
    }
    finally {
        Close-OracleResource -Object $command
        Close-OracleResource -Object $connection
    }
}