function Get-OracleExceptionMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $messages = New-Object System.Collections.Generic.List[string]
    $current = $Exception

    while ($current) {
        if ($current.Message -and -not $messages.Contains($current.Message)) {
            $messages.Add($current.Message)
        }

        $current = $current.InnerException
    }

    return ($messages -join ' | ')
}
