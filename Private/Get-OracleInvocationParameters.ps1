function Get-OracleInvocationParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$BoundParameters,

        [Parameter()]
        [ValidateSet('Query', 'ConnectionTest')]
        [string]$Target = 'Query'
    )

    $parameterNames = @(
        'ConnectionString',
        'Credential',
        'DataSource',
        'CredentialName',
        'CredentialDataSource',
        'ProfileName',
        'CredentialStorePath',
        'ProfileStorePath',
        'Log',
        'LogPath'
    )

    if ($Target -eq 'Query') {
        $parameterNames += @('CommandTimeout', 'LogSql', 'LogParameters')
    }
    else {
        $parameterNames += 'ConnectionTimeout'
    }

    $result = @{}
    foreach ($name in $parameterNames) {
        if ($BoundParameters.Keys -contains $name) {
            $result[$name] = $BoundParameters[$name]
        }
    }

    return $result
}
