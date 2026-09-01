function Complete-OracleOutputFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TempPath,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [switch]$NoClobber,

        [Parameter()]
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $TempPath -PathType Leaf)) {
        throw "Completed output file not found: $TempPath"
    }

    $targetPath = [System.IO.Path]::GetFullPath($Path)
    $targetExists = Test-Path -LiteralPath $targetPath -PathType Leaf

    if ($targetExists -and $NoClobber -and -not $Force) {
        throw "Output file already exists: $Path"
    }

    if ($targetExists) {
        $target = Get-Item -LiteralPath $targetPath
        if ($target.IsReadOnly) {
            if (-not $Force) {
                throw "Output file is read-only. Use -Force to replace it: $Path"
            }
            $target.IsReadOnly = $false
        }

        $backupPath = Join-Path -Path $target.DirectoryName -ChildPath ('.{0}.{1}.bak' -f $target.Name, [guid]::NewGuid().ToString('N'))
        $replacementSucceeded = $false
        try {
            [System.IO.File]::Replace(
                [System.IO.Path]::GetFullPath($TempPath),
                $targetPath,
                $backupPath
            )
            $replacementSucceeded = $true
        }
        finally {
            if ($replacementSucceeded -and (Test-Path -LiteralPath $backupPath)) {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        [System.IO.File]::Move([System.IO.Path]::GetFullPath($TempPath), $targetPath)
    }

    return $targetPath
}
