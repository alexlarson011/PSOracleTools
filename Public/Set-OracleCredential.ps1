<#
.SYNOPSIS
Stores an Oracle credential for reuse.

.DESCRIPTION
Stores a username and password for reuse. By default, the password is encrypted in the module's credential store.
When -SecretVault or -SecretName is supplied, the password is stored through Microsoft.PowerShell.SecretManagement and the credential store keeps only metadata.
You can supply a PSCredential directly or prompt interactively by providing -UserName.

.PARAMETER Name
Logical name used to retrieve the saved credential later.

.PARAMETER Credential
PSCredential to store.

.PARAMETER UserName
User name to prompt for when -Credential is not supplied.

.PARAMETER CredentialStorePath
Optional custom path to the credential store JSON file.

.PARAMETER SecretVault
Optional SecretManagement vault name used to store the password.

.PARAMETER SecretName
Optional SecretManagement secret name. Defaults to an Azure Key Vault compatible name derived from -Name.

.EXAMPLE
Set-OracleCredential -Name 'ProdLow' -UserName 'APP_USER'

Prompts for a password and stores the credential.

.EXAMPLE
Set-OracleCredential ProdLow APP_USER

Prompts for a password and stores the credential using positional arguments.

.EXAMPLE
Set-OracleCredential -Name 'ProdLow' -Credential $cred -CredentialStorePath '.\config\oracle-creds.json'

Stores a credential in a custom credential file.

.EXAMPLE
Set-OracleCredential -Name 'ProdLow' -Credential $cred -SecretVault 'AzKV'

Stores the password in a registered SecretManagement vault and stores only credential metadata in the module credential store.
#>
function Set-OracleCredential {
    [CmdletBinding(DefaultParameterSetName = 'ByUserName', PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByUserName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByCredential')]
        [string]$Name,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByCredential')]
        [PSCredential]$Credential,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByUserName')]
        [string]$UserName,

        [Parameter(ParameterSetName = 'ByUserName')]
        [Parameter(ParameterSetName = 'ByCredential')]
        [string]$CredentialStorePath,

        [Parameter(ParameterSetName = 'ByUserName')]
        [Parameter(ParameterSetName = 'ByCredential')]
        [string]$SecretVault,

        [Parameter(ParameterSetName = 'ByUserName')]
        [Parameter(ParameterSetName = 'ByCredential')]
        [string]$SecretName
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

    $useSecretManagement = $PSBoundParameters.ContainsKey('SecretVault') -or $PSBoundParameters.ContainsKey('SecretName')

    if ($useSecretManagement) {
        $availability = Test-OracleSecretManagementAvailable -RequiredCommand @('Set-Secret')
        if (-not $availability.Available) {
            throw ('Microsoft.PowerShell.SecretManagement is required for -SecretVault/-SecretName. Missing command(s): {0}' -f ($availability.MissingCommands -join ', '))
        }

        if (-not $SecretName) {
            $SecretName = New-OracleSecretName -Name $Name
        }

        $setSecretParameters = @{
            Name               = $SecretName
            SecureStringSecret = $Credential.Password
        }
        if ($SecretVault) {
            $setSecretParameters.Vault = $SecretVault
        }

        Set-Secret @setSecretParameters

        $newRecord = [pscustomobject]@{
            Name              = $Name
            UserName          = $Credential.UserName
            CredentialSource  = 'SecretManagement'
            SecretName        = $SecretName
            SecretVault       = $SecretVault
            EncryptedPassword = $null
            UpdatedOn         = Get-Date
        }
    }
    else {
        $newRecord = [pscustomobject]@{
            Name              = $Name
            UserName          = $Credential.UserName
            CredentialSource  = 'CredentialStore'
            SecretName        = $null
            SecretVault       = $null
            EncryptedPassword = Protect-OraclePassword -SecurePassword $Credential.Password
            UpdatedOn         = Get-Date
        }
    }

    $records += $newRecord
    $directory = Split-Path -Path $path -Parent
    if ($directory -and -not (Test-Path -Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
    $records | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8

    New-OracleResult -TypeName 'PSOracleTools.CredentialSetResult' -Property ([ordered]@{
        Success          = $true
        Operation        = 'Set-OracleCredential'
        Name             = $Name
        UserName         = $Credential.UserName
        CredentialSource = $newRecord.CredentialSource
        SecretName       = $newRecord.SecretName
        SecretVault      = $newRecord.SecretVault
        UpdatedOn        = $newRecord.UpdatedOn
        Path             = $path
    })
}
