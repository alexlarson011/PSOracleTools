# Changelog

All notable changes to this project are documented here.

## Unreleased

### Fixed

- Preserved Oracle alternative-quoted literals when parsing SQL files.
- Preserved duplicate query columns by assigning deterministic unique property names.
- Allowed CSV and procedure wrappers to inherit profile command timeout and logging defaults.
- Replaced completed delimited exports atomically so failed exports do not truncate an existing file.
- Detected conflicting in-process Oracle managed driver versions and file contents during initialization.
- Prevented duplicate confirmation prompts when invoking stored procedures.

### Changed

- Pinned the CI test environment to Pester 5.9.0.

## 1.1.1 - 2026-08-31

### Fixed

- Restored non-interactive defaults for write commands while keeping explicit `-WhatIf` and `-Confirm` support.
- Made credential and profile JSON updates lock-protected and atomic to avoid concurrent-writer data loss.

## 1.1.0 - 2026-08-31

### Added

- `-WhatIf` and `-Confirm` support for mutating Oracle commands and profile/credential writes.
- `Invoke-OracleSqlFile -Preview` for connection-free statement inspection and DDL classification.
- `Invoke-OracleQuery -MaxRows` to bound in-memory exploratory query results.
- `Get-OracleServerInfo` for database and session identity diagnostics.
- Pester regression coverage and a Windows PowerShell CI workflow.

### Changed

- Expanded operational, credential-portability, logging, compatibility, and scheduler documentation.

## 1.0.0 - 2026-04-25

- Initial public release with profiles, SecretManagement-backed credentials, query and execution commands, SQL-file transactions, and delimited/CSV/Excel exports.
