function Resolve-OracleConnectionProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName,

        [Parameter()]
        [string]$ProfileStorePath
    )

    $path = Get-OracleProfileStorePath -ProfileStorePath $ProfileStorePath

    if (-not (Test-Path -Path $path)) {
        throw "No profile store found at [$path]."
    }

    $profiles = @(Get-Content -Path $path -Raw | ConvertFrom-Json)
    $profile = $profiles | Where-Object { $_.Name -eq $ProfileName } | Select-Object -First 1

    if (-not $profile) {
        throw "Connection profile [$ProfileName] not found."
    }

    return $profile
}
