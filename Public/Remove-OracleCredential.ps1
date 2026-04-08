function Remove-OracleCredential {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$CredentialStorePath
    )

    $path = Get-OracleCredentialStorePath -CredentialStorePath $CredentialStorePath

    if (-not (Test-Path -Path $path)) {
        throw 'No credential store found.'
    }

    $records = @(Get-Content -Path $path -Raw | ConvertFrom-Json)
    $newRecords = @($records | Where-Object { $_.Name -ne $Name })

    if ($PSCmdlet.ShouldProcess($Name, 'Remove Oracle credential')) {
        $newRecords | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding UTF8
    }

    [pscustomobject]@{
        Name    = $Name
        Removed = ($records.Count -ne $newRecords.Count)
    }
}
