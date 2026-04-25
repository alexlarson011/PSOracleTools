function Resolve-OracleCredential {
    [CmdletBinding(DefaultParameterSetName = 'ByCredential')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByCredential')]
        [PSCredential]$Credential,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$CredentialName,

        [Parameter()]
        [string]$CredentialStorePath
    )

    switch ($PSCmdlet.ParameterSetName) {
        'ByCredential' {
            return $Credential
        }

        'ByName' {
            $record = Get-OracleCredential -Name $CredentialName -CredentialStorePath $CredentialStorePath

            $credentialSource = if ($record.PSObject.Properties['CredentialSource']) {
                [string]$record.CredentialSource
            }
            elseif ($record.PSObject.Properties['SecretName'] -and $record.SecretName) {
                'SecretManagement'
            }
            else {
                'CredentialStore'
            }

            if ($credentialSource -eq 'SecretManagement') {
                $availability = Test-OracleSecretManagementAvailable -RequiredCommand @('Get-Secret')
                if (-not $availability.Available) {
                    throw ('Microsoft.PowerShell.SecretManagement is required to resolve credential [{0}]. Missing command(s): {1}' -f $CredentialName, ($availability.MissingCommands -join ', '))
                }

                $getSecretParameters = @{
                    Name = [string]$record.SecretName
                }
                if ($record.PSObject.Properties['SecretVault'] -and $record.SecretVault) {
                    $getSecretParameters.Vault = [string]$record.SecretVault
                }

                $secret = Get-Secret @getSecretParameters
                if ($secret -is [PSCredential]) {
                    return $secret
                }
                elseif ($secret -is [Security.SecureString]) {
                    $securePassword = $secret
                }
                elseif ($secret -is [string]) {
                    $securePassword = ConvertTo-SecureString -String $secret -AsPlainText -Force
                }
                else {
                    throw "SecretManagement secret [$($record.SecretName)] must resolve to a SecureString, string, or PSCredential."
                }
            }
            else {
                $securePassword = Unprotect-OraclePassword -EncryptedString $record.EncryptedPassword
            }

            return New-Object System.Management.Automation.PSCredential(
                $record.UserName,
                $securePassword
            )
        }
    }
}
