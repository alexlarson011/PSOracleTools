# Optional Excel Automation

This folder contains optional helpers for workflows that require installed Microsoft Excel through COM automation.
These scripts are not imported or exported by the core `PSOracleTools` module.

Use this lane when you need real Excel behavior such as:

- filling a formatted workbook template once per Oracle row
- preserving charts, formulas, print areas, headers, footers, and workbook layout
- running an Excel macro after filling values
- exporting the completed workbook to PDF

Prefer the core `Export-OracleExcel` command when you only need a plain `.xlsx` export.
It does not require Excel and is safer for unattended automation.

## Risks

Excel COM automation is Windows-only and requires Microsoft Excel to be installed under the account running the script.
It is more fragile in unattended schedulers, services, in-process automation hosts, and parallel runs.

Common failure modes include:

- orphaned `EXCEL.EXE` processes if cleanup is interrupted
- macro/security/trust-center prompts
- protected-view or external-link prompts
- file overwrite prompts
- printer or PDF export prompts
- parallel runs fighting over templates or output paths

The helper sets `DisplayAlerts`, `EnableEvents`, and `AskToUpdateLinks` to reduce prompts, opens templates read-only, and closes Excel in `finally`.
Still, treat it as a controlled desktop/scheduled-task tool, not a high-volume server reporting engine.

## Usage

```powershell
Import-Module ..\..\PSOracleTools.psd1 -Force
. .\Invoke-OracleExcelTemplate.ps1

Invoke-OracleExcelTemplate `
  -ProfileName ps_tools `
  -Sql 'select movie_id, movie_nm, movie_rtg from movies order by movie_id' `
  -TemplatePath '.\templates\movie-template.xlsx' `
  -OutputDirectory '.\output' `
  -OutputFileNameTemplate 'Movie-{MOVIE_ID}.xlsx' `
  -WorksheetName 'Report' `
  -CellMap @{
      'B2' = 'MOVIE_ID'
      'B3' = 'MOVIE_NM'
      'B4' = 'MOVIE_RTG'
  } `
  -AutoFit
```

Run a macro after cell values are written:

```powershell
Invoke-OracleExcelTemplate `
  -ProfileName ps_tools `
  -SqlPath '.\queries\movie-reports.sql' `
  -TemplatePath '.\templates\movie-template.xlsm' `
  -OutputDirectory '.\output' `
  -OutputFileNameTemplate 'Movie-{MOVIE_ID}.xlsm' `
  -CellMap @{ 'B2' = 'MOVIE_ID'; 'B3' = 'MOVIE_NM' } `
  -RunMacro 'Module1.AfterFill'
```

Macro execution depends on Excel Trust Center settings and trusted file locations.
If macros are disabled or the macro name is unavailable, use `-ContinueOnError` to return failed row results instead of throwing immediately.
Unhandled errors inside the VBA macro may still open the Visual Basic debugger and block the automation run, depending on local VBE error-trapping settings. For unattended batches, wrap template macros in their own `On Error` handling and write any macro-specific status back into the workbook.

Return per-row failures instead of stopping at the first error:

```powershell
Invoke-OracleExcelTemplate `
  -ProfileName ps_tools `
  -Sql 'select movie_id, movie_nm from movies' `
  -TemplatePath '.\templates\movie-template.xlsx' `
  -OutputDirectory '.\output' `
  -OutputFileNameTemplate 'Movie-{MOVIE_ID}.xlsx' `
  -CellMap @{ 'B2' = 'MOVIE_ID'; 'B3' = 'MISSING_COLUMN' } `
  -ContinueOnError
```

Failed rows return `PSOracleTools.Optional.ExcelTemplateResult` objects with `Success = $false`, `ErrorType`, and `ErrorMessage`.

Export each filled template to PDF:

```powershell
Invoke-OracleExcelTemplate `
  -ProfileName ps_tools `
  -Sql 'select movie_id, movie_nm from movies' `
  -TemplatePath '.\templates\movie-template.xlsx' `
  -OutputDirectory '.\pdf' `
  -OutputFileNameTemplate 'Movie-{MOVIE_ID}.pdf' `
  -CellMap @{ 'B2' = 'MOVIE_ID'; 'B3' = 'MOVIE_NM' } `
  -SaveAs Pdf
```

For complex template filling, use `-EachWorkbook`:

```powershell
Invoke-OracleExcelTemplate `
  -ProfileName ps_tools `
  -Sql 'select * from movies' `
  -TemplatePath '.\templates\movie-template.xlsx' `
  -OutputDirectory '.\output' `
  -OutputFileNameTemplate 'Movie-{MOVIE_ID}.xlsx' `
  -EachWorkbook {
      param($Workbook, $Worksheet, $Row)

      $Worksheet.Cells.Item(2, 2).Value2 = $Row.MOVIE_ID
      $Worksheet.Cells.Item(3, 2).Value2 = $Row.MOVIE_NM
      $Worksheet.Cells.Item(4, 2).Value2 = $Row.GENRE
  }
```

When writing custom `-EachWorkbook` logic, prefer `Cells.Item(row, column)` or `Range('B2','B2')` over the single-argument `Range('B2')` shorthand.
PowerShell's Excel COM binder can be sensitive to mixed value types at repeated assignment sites.
