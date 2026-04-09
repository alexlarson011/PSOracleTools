<#
.SYNOPSIS
Removes a saved Oracle connection profile.

.DESCRIPTION
Deletes a named connection profile from the configured profile store.

.PARAMETER Name
Profile name to remove.

.PARAMETER ProfileStorePath
Optional custom path to the profile store JSON file.

.EXAMPLE
Remove-OracleConnectionProfile -Name 'ProdLow' -Confirm:$false

Removes a stored connection profile without prompting.
#>
function Remove-OracleConnectionProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$ProfileStorePath
    )

    $path = Get-OracleProfileStorePath -ProfileStorePath $ProfileStorePath

    if (-not (Test-Path -Path $path)) {
        throw "No profile store found at [$path]."
    }

    $profiles = Read-OracleNamedRecordStore -Path $path -StoreDescription 'connection profile'
    $newProfiles = @($profiles | Where-Object { $_.Name -ne $Name })

    if ($PSCmdlet.ShouldProcess($Name, 'Remove Oracle connection profile')) {
        $newProfiles | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8
    }

    [pscustomobject]@{
        Name    = $Name
        Removed = ($profiles.Count -ne $newProfiles.Count)
    }
}
