function Update-OracleNamedRecordStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$StoreDescription,

        [Parameter(Mandatory)]
        [scriptblock]$Update,

        [Parameter()]
        [ValidateRange(1, 120)]
        [int]$LockTimeoutSeconds = 30
    )

    $ErrorActionPreference = 'Stop'

    if (-not ('PSOracleTools.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace PSOracleTools {
    public static class NativeMethods {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool MoveFileEx(string existingFileName, string newFileName, int flags);
    }
}
'@
    }

    $directory = Split-Path -Path $Path -Parent
    $tempDirectory = if ($directory) { $directory } else { [System.IO.Path]::GetFullPath('.') }
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $lockPath = '{0}.lock' -f $Path
    $deadline = (Get-Date).AddSeconds($LockTimeoutSeconds)
    $lockStream = $null
    $lockAcquired = $false

    while ($null -eq $lockStream) {
        try {
            $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $lockAcquired = $true
        }
        catch [System.IO.IOException] {
            if ((Get-Date) -ge $deadline) {
                throw "Timed out waiting for exclusive access to the $StoreDescription store at [$Path]."
            }

            Start-Sleep -Milliseconds 100
        }
    }

    $tempPath = $null
    try {
        $records = @(Read-OracleNamedRecordStore -Path $Path -StoreDescription $StoreDescription)
        $state = @{}
        $updatedRecords = @(& $Update $records $state)
        $json = ConvertTo-Json -InputObject @($updatedRecords) -Depth 5
        $tempPath = Join-Path -Path $tempDirectory -ChildPath ('.{0}.{1}.tmp' -f ([System.IO.Path]::GetFileName($Path)), [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($true)))

        $replaceExistingAndWriteThrough = 0x1 -bor 0x8
        if (-not [PSOracleTools.NativeMethods]::MoveFileEx($tempPath, [System.IO.Path]::GetFullPath($Path), $replaceExistingAndWriteThrough)) {
            $win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Failed to atomically update the $StoreDescription store at [$Path]. Windows error code: $win32Error."
        }

        return [pscustomobject]@{
            Records = $updatedRecords
            State   = $state
        }
    }
    finally {
        if ($tempPath -and (Test-Path -LiteralPath $tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }

        if ($lockStream) {
            $lockStream.Dispose()
        }

        if ($lockAcquired) {
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        }
    }
}
