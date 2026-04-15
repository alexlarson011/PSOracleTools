param(
    [Parameter(Mandatory)]
    [string]$ScriptPath,

    [Parameter()]
    [string[]]$ScriptArguments = @(),

    [Parameter()]
    [string]$WorkingDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedScriptPath = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath

if (-not $WorkingDirectory) {
    $WorkingDirectory = Split-Path -Path $resolvedScriptPath -Parent
}

$powershellExe = if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    Join-Path -Path $env:WINDIR -ChildPath 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
}
else {
    Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

$invocationArguments = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $resolvedScriptPath
) + $ScriptArguments

Push-Location -LiteralPath $WorkingDirectory
try {
    & $powershellExe @invocationArguments
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
}
finally {
    Pop-Location
}

exit $exitCode
