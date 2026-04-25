<#
.SYNOPSIS
Runs a script in a fresh Windows PowerShell process.

.DESCRIPTION
Starts powershell.exe out-of-process and invokes the target script with optional arguments.
Use this wrapper when an automation host, such as JAMS in-process PowerShell, has assembly-loading or host-state issues that do not occur in a normal Windows PowerShell session.

.PARAMETER ScriptPath
Path to the PowerShell script to run in the fresh process.

.PARAMETER ScriptArguments
Optional arguments passed through to the target script.

.PARAMETER WorkingDirectory
Working directory for the child PowerShell process. Defaults to the target script's directory.

.EXAMPLE
.\scripts\Invoke-InFreshWindowsPowerShell.ps1 -ScriptPath 'F:\SCHED_JOBS\Finance\meu\MEUInterfaceLoad.ps1'

Runs the target script in a fresh Windows PowerShell process.

.EXAMPLE
.\scripts\Invoke-InFreshWindowsPowerShell.ps1 -ScriptPath '.\job.ps1' -ScriptArguments @('one', 'two') -WorkingDirectory '.\jobs'

Runs a script with positional arguments from a specific working directory.
#>
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
