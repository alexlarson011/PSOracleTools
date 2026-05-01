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
[CmdletBinding()]
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

$exitCode = 1

try {
    $resolvedScriptPath = (Resolve-Path -LiteralPath $ScriptPath -ErrorAction Stop).ProviderPath

    if (-not $WorkingDirectory) {
        $WorkingDirectory = Split-Path -Path $resolvedScriptPath -Parent
    }

    $resolvedWorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory -ErrorAction Stop).ProviderPath

    $powershellExe = if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
        Join-Path -Path $env:WINDIR -ChildPath 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    }
    else {
        Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    if (-not (Test-Path -LiteralPath $powershellExe)) {
        throw "Windows PowerShell executable was not found at: $powershellExe"
    }

    $invocationArguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $resolvedScriptPath
    ) + $ScriptArguments

    Write-Output "Starting child Windows PowerShell process."
    Write-Output "Script path: $resolvedScriptPath"
    Write-Output "Working directory: $resolvedWorkingDirectory"

    Push-Location -LiteralPath $resolvedWorkingDirectory
    try {
        & $powershellExe @invocationArguments

        $exitCode = if ($null -ne $LASTEXITCODE) {
            [int]$LASTEXITCODE
        }
        else {
            0
        }
    }
    finally {
        Pop-Location
    }

    Write-Output "Child PowerShell process exit code: $exitCode"

    if ($exitCode -ne 0) {
        throw "Child PowerShell process failed with exit code: $exitCode"
    }
}
catch {
    Write-Error "Invoke-InFreshWindowsPowerShell failed. $($_.Exception.Message)"
    throw
}

exit 0