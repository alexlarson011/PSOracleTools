function Test-OracleSecretManagementAvailable {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$RequiredCommand = @('Get-Secret', 'Set-Secret', 'Remove-Secret', 'Get-SecretVault')
    )

    $missingCommands = @(
        foreach ($commandName in $RequiredCommand) {
            if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
                $commandName
            }
        }
    )

    [pscustomobject]@{
        Available       = ($missingCommands.Count -eq 0)
        MissingCommands = $missingCommands
    }
}
