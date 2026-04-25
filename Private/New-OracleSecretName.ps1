function New-OracleSecretName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Name)
        $hashBytes = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }

    $hash = ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').Substring(0, 8).ToLowerInvariant()
    $safeName = ($Name -replace '[^A-Za-z0-9-]', '-').Trim('-')

    if ([string]::IsNullOrWhiteSpace($safeName)) {
        $safeName = 'Credential'
    }

    $prefix = 'PSOracleTools'
    $maxNameLength = 127 - $prefix.Length - $hash.Length - 2
    if ($safeName.Length -gt $maxNameLength) {
        $safeName = $safeName.Substring(0, $maxNameLength).Trim('-')
    }

    return '{0}-{1}-{2}' -f $prefix, $safeName, $hash
}
