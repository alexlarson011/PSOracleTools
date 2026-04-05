function Unprotect-OraclePassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EncryptedString
    )

    return ConvertTo-SecureString -String $EncryptedString
}