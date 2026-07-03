# Changelog

All notable changes to **sql-audit-skill** are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/). The authoritative version is the `version` field in
[`.claude-plugin/plugin.json`](.claude-plugin/plugin.json); bump it on every release (see the
marketplace [`RELEASING.md`](../../RELEASING.md)).

## [Unreleased]

## [0.1.0] - 2026-07-03
### Added
- Initial release: audits a SQL Server database against Joe Celko's *SQL Programming Style*
  (18 rules across naming, data-type/DDL, view, and coding categories) and writes a
  severity-tiered findings report from read-only `sqlcmd` catalog queries.
- `sqlcmd` auto-detection (PATH, winget go-sqlcmd, ODBC/SSMS/VS bundled tools) with an offer to
  install go-sqlcmd when none is found.
- Secure SQL-auth credential handling: prefer trusted auth (`-E`); otherwise store the password in
  Windows Credential Manager (DPAPI, user-scoped) and pass it via `SQLCMDPASSWORD` — never `-P` on
  the command line. Includes a `--store` setup mode for first-time credential storage.
- go-sqlcmd connection-context support for reusable named targets.
- Regression fixture under `tests/` covering the six rules absent from AdventureWorks.
