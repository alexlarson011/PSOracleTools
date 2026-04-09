<#
.SYNOPSIS
Stores an Oracle credential for reuse.

.DESCRIPTION
Stores a username and encrypted password in the module's credential store.
You can supply a PSCredential directly or prompt interactively by providing -UserName.

.PARAMETER Name
Logical name used to retrieve the saved credential later.

.PARAMETER Credential
PSCredential to store.

.PARAMETER UserName
User name to prompt for when -Credential is not supplied.

.PARAMETER CredentialStorePath
Optional custom path to the credential store JSON file.

.EXAMPLE
Set-OracleCredential -Name 'ProdLow' -UserName 'APP_USER'

Prompts for a password and stores the credential.

.EXAMPLE
Set-OracleCredential -Name 'ProdLow' -Credential $cred -CredentialStorePath '.\config\oracle-creds.json'

Stores a credential in a custom credential file.
#>
function Set-OracleCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [string]$UserName,

        [Parameter()]
        [string]$CredentialStorePath
    )

    if (-not $Credential) {
        if (-not $UserName) {
            throw 'Provide either -Credential or -UserName.'
        }

        $Credential = Get-Credential -UserName $UserName -Message "Enter Oracle password for [$Name]"
    }

    $path = Get-OracleCredentialStorePath -CredentialStorePath $CredentialStorePath
    $records = @()

    if (Test-Path -Path $path) {
        $records = Read-OracleNamedRecordStore -Path $path -StoreDescription 'credential'
    }

    $records = @($records | Where-Object { $_.Name -ne $Name })

    $newRecord = [pscustomobject]@{
        Name              = $Name
        UserName          = $Credential.UserName
        EncryptedPassword = Protect-OraclePassword -SecurePassword $Credential.Password
        UpdatedOn         = Get-Date
    }

    $records += $newRecord
    $directory = Split-Path -Path $path -Parent
    if ($directory -and -not (Test-Path -Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
    $records | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8

    [pscustomobject]@{
        Name      = $Name
        UserName  = $Credential.UserName
        UpdatedOn = $newRecord.UpdatedOn
        Path      = $path
    }
}
