<#
.SYNOPSIS
Removes a saved Oracle credential from the credential store.

.DESCRIPTION
Deletes a named credential record from the configured credential store.
Supports ShouldProcess so it can be used with -WhatIf and -Confirm.

.PARAMETER Name
Credential name to remove.

.PARAMETER CredentialStorePath
Optional custom path to the credential store JSON file.

.PARAMETER RemoveSecret
Also removes the backing SecretManagement secret when the credential record uses SecretManagement.

.EXAMPLE
Remove-OracleCredential -Name 'ProdLow' -Confirm:$false

Removes a saved credential without prompting.
#>
function Remove-OracleCredential {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$CredentialStorePath,

        [Parameter()]
        [switch]$RemoveSecret
    )

    $path = Get-OracleCredentialStorePath -CredentialStorePath $CredentialStorePath

    if (-not (Test-Path -Path $path)) {
        throw 'No credential store found.'
    }

    $records = @(Read-OracleNamedRecordStore -Path $path -StoreDescription 'credential')
    $record = $records | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    $newRecords = @($records | Where-Object { $_.Name -ne $Name })

    if ($PSCmdlet.ShouldProcess($Name, 'Remove Oracle credential')) {
        if ($RemoveSecret -and $record -and $record.PSObject.Properties['SecretName'] -and $record.SecretName) {
            $availability = Test-OracleSecretManagementAvailable -RequiredCommand @('Remove-Secret')
            if (-not $availability.Available) {
                throw ('Microsoft.PowerShell.SecretManagement is required for -RemoveSecret. Missing command(s): {0}' -f ($availability.MissingCommands -join ', '))
            }

            $removeSecretParameters = @{
                Name = [string]$record.SecretName
            }
            if ($record.PSObject.Properties['SecretVault'] -and $record.SecretVault) {
                $removeSecretParameters.Vault = [string]$record.SecretVault
            }
            Remove-Secret @removeSecretParameters
        }

        $newRecords | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8
    }

    [pscustomobject]@{
        Name          = $Name
        Removed       = ($records.Count -ne $newRecords.Count)
        SecretRemoved = [bool]($RemoveSecret -and $record -and $record.PSObject.Properties['SecretName'] -and $record.SecretName)
    }
}
