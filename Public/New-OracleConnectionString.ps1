function New-OracleConnectionString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataSource,

        [Parameter(Mandatory)]
        [string]$UserId,

        [Parameter(Mandatory)]
        [string]$Password,

        [Parameter()]
        [bool]$Pooling = $true,

        [Parameter()]
        [int]$MinPoolSize = 1,

        [Parameter()]
        [int]$MaxPoolSize = 10
    )

    $builder = New-Object System.Text.StringBuilder

    [void]$builder.Append("User Id=$UserId;")
    [void]$builder.Append("Password=$Password;")
    [void]$builder.Append("Data Source=$DataSource;")
    [void]$builder.Append("Pooling=$Pooling;")
    [void]$builder.Append("Min Pool Size=$MinPoolSize;")
    [void]$builder.Append("Max Pool Size=$MaxPoolSize;")

    return $builder.ToString()
}