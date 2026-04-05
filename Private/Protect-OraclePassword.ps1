function Protect-OraclePassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Security.SecureString]$SecurePassword
    )

    return ConvertFrom-SecureString -SecureString $SecurePassword
}