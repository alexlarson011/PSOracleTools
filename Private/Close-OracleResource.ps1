function Close-OracleResource {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Object
    )

    if ($null -eq $Object) {
        return
    }

    try {
        if ($Object -is [System.IDisposable]) {
            $Object.Dispose()
        }
    }
    catch {
        Write-Verbose "Failed to dispose resource: $($_.Exception.Message)"
    }
}