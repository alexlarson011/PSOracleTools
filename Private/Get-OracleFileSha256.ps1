function Get-OracleFileSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $stream = $null
    $sha256 = $null
    try {
        $stream = [System.IO.File]::OpenRead([System.IO.Path]::GetFullPath($Path))
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hash = $sha256.ComputeHash($stream)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '')
    }
    finally {
        Close-OracleResource -Object $sha256
        Close-OracleResource -Object $stream
    }
}
