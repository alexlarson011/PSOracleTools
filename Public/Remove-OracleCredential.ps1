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

.EXAMPLE
Remove-OracleCredential ProdLow -Confirm:$false

Removes a saved credential using a positional name.
#>
function Remove-OracleCredential {
    [CmdletBinding(SupportsShouldProcess, PositionalBinding = $false)]
    param(
        [Parameter(Mandatory, Position = 0)]
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

    if ($PSCmdlet.ShouldProcess($Name, 'Remove Oracle credential')) {
        $updateResult = Update-OracleNamedRecordStore -Path $path -StoreDescription 'credential' -Update {
            param($records, $state)

            $state['Record'] = $records | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
            if ($RemoveSecret -and $state['Record'] -and $state['Record'].PSObject.Properties['SecretName'] -and $state['Record'].SecretName) {
                $availability = Test-OracleSecretManagementAvailable -RequiredCommand @('Remove-Secret')
                if (-not $availability.Available) {
                    throw ('Microsoft.PowerShell.SecretManagement is required for -RemoveSecret. Missing command(s): {0}' -f ($availability.MissingCommands -join ', '))
                }

                $removeSecretParameters = @{ Name = [string]$state['Record'].SecretName }
                if ($state['Record'].PSObject.Properties['SecretVault'] -and $state['Record'].SecretVault) {
                    $removeSecretParameters.Vault = [string]$state['Record'].SecretVault
                }
                Remove-Secret @removeSecretParameters
            }

            return @($records | Where-Object { $_.Name -ne $Name })
        }

        $record = $updateResult.State['Record']
        $removed = ($null -ne $record)
    }
    else {
        $record = $null
        $removed = $false
    }

    New-OracleResult -TypeName 'PSOracleTools.CredentialRemoveResult' -Property ([ordered]@{
        Success       = $true
        Operation     = 'Remove-OracleCredential'
        Name          = $Name
        Removed       = $removed
        SecretRemoved = [bool]($RemoveSecret -and $record -and $record.PSObject.Properties['SecretName'] -and $record.SecretName)
    })
}
