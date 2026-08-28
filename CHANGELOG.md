# Changelog

All notable changes to this project are documented here.

## 1.1.0 - Unreleased

### Added

- `-WhatIf` and `-Confirm` support for mutating Oracle commands and profile/credential writes.
- `Invoke-OracleSqlFile -Preview` for connection-free statement inspection and DDL classification.
- `Invoke-OracleQuery -MaxRows` to bound in-memory exploratory query results.
- `Get-OracleServerInfo` for database and session identity diagnostics.
- Pester regression coverage and a Windows PowerShell CI workflow.

### Changed

- Expanded operational, credential-portability, logging, compatibility, and scheduler documentation.

## 1.0.0

- Initial public release with profiles, SecretManagement-backed credentials, query and execution commands, SQL-file transactions, and delimited/CSV/Excel exports.
