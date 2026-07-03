# sql-audit-skill

A Claude Code plugin that audits a **SQL Server** database against the rules in
*[Joe Celko's SQL Programming Style](https://www.elsevier.com/books/joe-celkos-sql-programming-style/celko/978-0-12-088797-2)*
(Morgan-Kaufmann, 2005). It runs **read-only** catalog queries through `sqlcmd` and produces a
severity-tiered findings report.

## What it checks

18 rules distilled from the book, tiered by severity:

| Severity | Meaning |
|----------|---------|
| **ERROR** | Objective violation |
| **WARN**  | Deprecated / portability risk |
| **INFO**  | Opinionated / Celko preference — review, don't necessarily "fix" |

| ID | Sev | Rule | Book |
|----|-----|------|------|
| N01 | WARN | Identifier length > 30 | §1.1.1 |
| N02 | ERROR | Non-standard identifier characters | §1.1.2 |
| N03 | WARN | Name requires quoting (reserved word / space) | §1.1.3 |
| N04 | INFO | Descriptive/Hungarian prefix (`tbl_`, `sp_`, …) | §1.2.3 |
| N05 | INFO | CamelCase column name | §2.1.2 |
| N06 | INFO | Missing ISO-11179 postfix | §1.2.4 |
| N07 | INFO | Generic `id` primary key | §1.2.3 |
| D01 | ERROR | Table has no PRIMARY KEY (heap) | §3.4 |
| D02 | INFO | IDENTITY used as key | §1.3.3 |
| D03 | INFO | `uniqueidentifier` primary key | §1.3.3 |
| D04 | ERROR | FLOAT/REAL column | §3.8.4 |
| D05 | WARN | Deprecated/proprietary type (TEXT/NTEXT/IMAGE/MONEY/…) | §3.3 |
| D06 | WARN | System-generated constraint name | §3.7 |
| D07 | INFO | Numeric column without range CHECK | §3.8.1 |
| V01 | WARN | `SELECT *` in view | §7.1.1 |
| C01 | INFO | Trigger present (prefer DRI) | §6.5 |
| C02 | WARN | Optimizer hint in module (NOLOCK/…) | §6.4 |
| C03 | WARN | Legacy `*=` / `=*` outer join | §6.1.1 |
| C04 | INFO | Proprietary function (GETDATE/ISNULL) | §6.1.4 |

Full rationale, exceptions, and remediation per rule: [`skills/sql-audit/references/celko-rules.md`](skills/sql-audit/references/celko-rules.md).

## Requirements

- **Claude Code** with plugin support.
- **`sqlcmd`** — the plugin auto-detects an existing install (PATH, winget go-sqlcmd, or the
  ODBC/SSMS/VS bundled tools). If missing it offers to install the open-source
  [go-sqlcmd](https://github.com/microsoft/go-sqlcmd) via `winget install sqlcmd`.
- A login with **`VIEW DEFINITION`** on the target database (needed for the view/module rules).

## Usage

```
/sql-audit localhost MyDatabase -E
/sql-audit tcp:host,1433 MyDatabase -U appuser -P ****
```

Or just ask: *"audit the MyDatabase database on localhost."* The plugin will:

1. Locate `sqlcmd` (prompting before any install).
2. Confirm server / database / auth.
3. Run [`skills/sql-audit/queries/audit.sql`](skills/sql-audit/queries/audit.sql) (read-only).
4. Write **`audit-report.md`** grouped by severity, with book citations and fixes.

## Credentials

Nothing is persisted by default — connection details exist only for a single run. Prefer
**trusted auth** (`-E`); for SQL logins the password is passed via the **`SQLCMDPASSWORD`** env var
(never `-P` on the command line, never a slash-command argument — both would land in the process
list and the Claude Code transcript). For repeat audits you can opt into go-sqlcmd *contexts* or
keep non-secret server/database defaults in a local settings file. See
[`references/sqlcmd-setup.md`](skills/sql-audit/references/sqlcmd-setup.md#credentials--connection-info).

## How it works

The audit is a single self-labeling SQL script that `UNION ALL`s every rule into one result set
(`severity | rule_id | rule_name | schema_name | object_name | detail`), read via
`sqlcmd -s "|" -W -h -1`. It touches only the system catalog and `sys.sql_modules` — nothing is
modified.

Rules **N06** and **D07** use `STRING_AGG` (SQL Server 2017+); on older engines comment those two
blocks out or note them as skipped.

Module-text rules (V01, C02–C04) are heuristic string matches and may hit comments or string
literals — the skill reviews flagged definitions before reporting.

## Layout

```
.claude-plugin/plugin.json     manifest
commands/sql-audit.md          /sql-audit command
skills/sql-audit/
  SKILL.md                     orchestration
  references/celko-rules.md    rule catalog (rationale + citations)
  references/sqlcmd-setup.md   sqlcmd detection & install
  queries/audit.sql            the read-only audit
scripts/detect-sqlcmd.ps1      locate sqlcmd
```

## License

MIT — see [LICENSE](LICENSE). Rule *content* derives from Joe Celko's book; this plugin is an
independent implementation of checks inspired by it.
