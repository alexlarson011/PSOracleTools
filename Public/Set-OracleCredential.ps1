function Set-OracleCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [string]$UserName
    )

    if (-not $Credential) {
        if (-not $UserName) {
            throw 'Provide either -Credential or -UserName.'
        }

        $Credential = Get-Credential -UserName $UserName -Message "Enter Oracle password for [$Name]"
    }

    $path = Get-OracleCredentialStorePath
    $records = @()

    if (Test-Path -Path $path) {
        $records = Get-Content -Path $path -Raw | ConvertFrom-Json
    }

    $records = @($records | Where-Object { $_.Name -ne $Name })

    $newRecord = [pscustomobject]@{
        Name              = $Name
        UserName          = $Credential.UserName
        EncryptedPassword = Protect-OraclePassword -SecurePassword $Credential.Password
        UpdatedOn         = Get-Date
    }

    $records += $newRecord
    $records | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8

    [pscustomobject]@{
        Name      = $Name
        UserName  = $Credential.UserName
        UpdatedOn = $newRecord.UpdatedOn
        Path      = $path
    }
}