function Read-OracleNamedRecordStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$StoreDescription
    )

    if (-not (Test-Path -Path $Path)) {
        return @()
    }

    $raw = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    try {
        $parsed = $raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to read the $StoreDescription store at [$Path]. Ensure the file contains valid JSON. $(Get-OracleExceptionMessage -Exception $_.Exception)"
    }

    $records = @($parsed)
    $invalidRecord = $records |
        Where-Object {
            $null -eq $_ -or
            $null -eq $_.PSObject.Properties['Name']
        } |
        Select-Object -First 1

    if ($invalidRecord) {
        throw "The $StoreDescription store at [$Path] must contain one or more JSON objects with a Name property."
    }

    return $records
}
