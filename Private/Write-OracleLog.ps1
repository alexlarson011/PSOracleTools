function Write-OracleLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [ValidateSet('INFO', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $entry = '[{0}] [{1}] {2}' -f $timestamp, $Level, $Message

    Write-Information $entry -InformationAction Continue

    if ($Path) {
        $directory = Split-Path -Path $Path -Parent
        if ($directory -and -not (Test-Path -Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }

        Add-Content -Path $Path -Value $entry -Encoding UTF8
    }
}
