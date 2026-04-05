function Resolve-OracleCredential {
    [CmdletBinding(DefaultParameterSetName = 'ByCredential')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByCredential')]
        [PSCredential]$Credential,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$CredentialName
    )

    switch ($PSCmdlet.ParameterSetName) {
        'ByCredential' {
            return $Credential
        }

        'ByName' {
            $record = Get-OracleCredential -Name $CredentialName
            $securePassword = Unprotect-OraclePassword -EncryptedString $record.EncryptedPassword

            return New-Object System.Management.Automation.PSCredential(
                $record.UserName,
                $securePassword
            )
        }
    }
}