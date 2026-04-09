function Split-OracleScriptStatements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    function Get-StatementKind {
        param(
            [Parameter(Mandatory)]
            [string]$StatementText
        )

        $candidate = $StatementText

        while ($true) {
            if ($candidate -match '^\s+') {
                $candidate = $candidate.Substring($matches[0].Length)
                continue
            }

            if ($candidate -match '^(?:--[^\n]*(?:\n|$))') {
                $candidate = $candidate.Substring($matches[0].Length)
                continue
            }

            if ($candidate -match '^(?s)/\*.*?\*/') {
                $candidate = $candidate.Substring($matches[0].Length)
                continue
            }

            break
        }

        if ([string]::IsNullOrWhiteSpace($candidate)) {
            return 'Sql'
        }

        if (Test-OraclePlSqlLikeText -Text $candidate) {
            return 'PlSql'
        }

        return 'Sql'
    }

    function New-ParsedStatement {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$StatementText,

            [Parameter(Mandatory)]
            [string]$Kind,

            [Parameter(Mandatory)]
            [int]$Index
        )

        $mode = if ($Kind -eq 'PlSql') { 'PlSql' } else { 'Sql' }
        $normalizedStatement = Normalize-OracleCommandText -Text $StatementText -Mode $mode
        if ([string]::IsNullOrWhiteSpace($normalizedStatement)) {
            return $null
        }

        if (Test-OracleClientDirective -StatementText $normalizedStatement) {
            return $null
        }

        return [pscustomobject]@{
            Index = $Index
            Kind  = $Kind
            Text  = $normalizedStatement
        }
    }

    $normalizedText = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $buffer = New-Object System.Text.StringBuilder
    $statements = New-Object System.Collections.Generic.List[object]
    $lineBuilder = New-Object System.Text.StringBuilder
    $statementIndex = 0

    $inSingleQuote = $false
    $inDoubleQuote = $false
    $inLineComment = $false
    $inBlockComment = $false
    $statementKind = 'Sql'

    for ($i = 0; $i -lt $normalizedText.Length; $i++) {
        $char = $normalizedText[$i]
        $nextChar = if ($i + 1 -lt $normalizedText.Length) { $normalizedText[$i + 1] } else { [char]0 }

        if ($inLineComment) {
            [void]$buffer.Append($char)
            if ($char -eq "`n") {
                $inLineComment = $false
                $lineBuilder.Clear() | Out-Null
            }
            else {
                [void]$lineBuilder.Append($char)
            }
            continue
        }

        if ($inBlockComment) {
            [void]$buffer.Append($char)
            if ($char -eq '*' -and $nextChar -eq '/') {
                [void]$buffer.Append($nextChar)
                $i += 1
                $inBlockComment = $false
            }

            if ($char -eq "`n") {
                $lineBuilder.Clear() | Out-Null
            }
            else {
                [void]$lineBuilder.Append($char)
            }
            continue
        }

        if ($inSingleQuote) {
            [void]$buffer.Append($char)
            if ($char -eq "'") {
                if ($nextChar -eq "'") {
                    [void]$buffer.Append($nextChar)
                    $i += 1
                    if ($nextChar -ne "`n") {
                        [void]$lineBuilder.Append($char)
                        [void]$lineBuilder.Append($nextChar)
                    }
                }
                else {
                    $inSingleQuote = $false
                }
            }

            if ($char -eq "`n") {
                $lineBuilder.Clear() | Out-Null
            }
            else {
                [void]$lineBuilder.Append($char)
            }
            continue
        }

        if ($inDoubleQuote) {
            [void]$buffer.Append($char)
            if ($char -eq '"') {
                if ($nextChar -eq '"') {
                    [void]$buffer.Append($nextChar)
                    $i += 1
                    if ($nextChar -ne "`n") {
                        [void]$lineBuilder.Append($char)
                        [void]$lineBuilder.Append($nextChar)
                    }
                }
                else {
                    $inDoubleQuote = $false
                }
            }

            if ($char -eq "`n") {
                $lineBuilder.Clear() | Out-Null
            }
            else {
                [void]$lineBuilder.Append($char)
            }
            continue
        }

        if ($char -eq '-' -and $nextChar -eq '-') {
            [void]$buffer.Append($char)
            [void]$buffer.Append($nextChar)
            $i += 1
            [void]$lineBuilder.Append($char)
            [void]$lineBuilder.Append($nextChar)
            $inLineComment = $true
            continue
        }

        if ($char -eq '/' -and $nextChar -eq '*') {
            [void]$buffer.Append($char)
            [void]$buffer.Append($nextChar)
            $i += 1
            [void]$lineBuilder.Append($char)
            [void]$lineBuilder.Append($nextChar)
            $inBlockComment = $true
            continue
        }

        if ($char -eq "'") {
            [void]$buffer.Append($char)
            [void]$lineBuilder.Append($char)
            $inSingleQuote = $true
            continue
        }

        if ($char -eq '"') {
            [void]$buffer.Append($char)
            [void]$lineBuilder.Append($char)
            $inDoubleQuote = $true
            continue
        }

        if ($char -eq "`n") {
            [void]$buffer.Append($char)
            $lineBuilder.Clear() | Out-Null
            $statementKind = Get-StatementKind -StatementText $buffer.ToString()
            continue
        }

        $linePrefix = $lineBuilder.ToString()
        $lineHasOnlyWhitespace = [string]::IsNullOrWhiteSpace($linePrefix)
        if ($char -eq '/' -and $statementKind -eq 'PlSql' -and $lineHasOnlyWhitespace) {
            $remainder = $normalizedText.Substring($i)
            if ($remainder -match '^/\s*(?:\n|$)') {
                $parsedStatement = $null
                if (-not [string]::IsNullOrWhiteSpace($buffer.ToString())) {
                    $parsedStatement = New-ParsedStatement -StatementText $buffer.ToString() -Kind $statementKind -Index ($statementIndex + 1)
                }
                if ($null -ne $parsedStatement) {
                    $statementIndex += 1
                    $statements.Add($parsedStatement) | Out-Null
                }
                $buffer.Clear() | Out-Null
                $lineBuilder.Clear() | Out-Null
                $statementKind = 'Sql'
                $i += $matches[0].Length - 1
                continue
            }
        }

        if ($char -eq ';' -and $statementKind -eq 'Sql') {
            $parsedStatement = $null
            if (-not [string]::IsNullOrWhiteSpace($buffer.ToString())) {
                $parsedStatement = New-ParsedStatement -StatementText $buffer.ToString() -Kind $statementKind -Index ($statementIndex + 1)
            }
            if ($null -ne $parsedStatement) {
                $statementIndex += 1
                $statements.Add($parsedStatement) | Out-Null
            }
            $buffer.Clear() | Out-Null
            $lineBuilder.Clear() | Out-Null
            $statementKind = 'Sql'
            continue
        }

        [void]$buffer.Append($char)
        [void]$lineBuilder.Append($char)
        $statementKind = Get-StatementKind -StatementText $buffer.ToString()
    }

    $parsedStatement = $null
    if (-not [string]::IsNullOrWhiteSpace($buffer.ToString())) {
        $parsedStatement = New-ParsedStatement -StatementText $buffer.ToString() -Kind $statementKind -Index ($statementIndex + 1)
    }
    if ($null -ne $parsedStatement) {
        $statements.Add($parsedStatement) | Out-Null
    }
    return $statements
}
