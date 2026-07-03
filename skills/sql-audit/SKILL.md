---
name: sql-audit
description: Audit a SQL Server database for conformance to Joe Celko's SQL Programming Style. Use when the user wants to audit, lint, or review a SQL Server database schema, check naming conventions, find heap tables / missing primary keys, flag FLOAT/deprecated types, unnamed constraints, SELECT * views, optimizer hints, or generate a database style report. Connects via sqlcmd and produces a severity-tiered findings report.
---

# SQL Server Style Audit (Celko)

Audit a live SQL Server database against the rules distilled from *Joe Celko's SQL
Programming Style*. The audit is **read-only**: it queries the system catalog and
`sys.sql_modules` only — no data or schema is modified.

## Workflow

### 1. Locate sqlcmd
Run the detector and capture the resolved path:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/detect-sqlcmd.ps1"
```

- Exit 0 → stdout is the full path to `sqlcmd`. Use it for step 3.
- Exit 1 → sqlcmd is missing. **Show the printed guidance and ask the user** before
  installing anything. If they approve, run `winget install sqlcmd`, then re-run the
  detector. Do **not** auto-install without confirmation.

See `references/sqlcmd-setup.md` for the probed locations and install details.

### 2. Collect connection parameters
Ask the user (or read non-secret values from the `/sql-audit` command arguments):

- **Server** (`-S`), e.g. `localhost`, `localhost\SQLEXPRESS`, `tcp:host,1433`.
- **Database** (`-d`) — the database to audit.
- **Auth**: Windows/trusted → `-E` (**default, no credentials**); SQL login → `-U <user>` + password.

**Credential handling — read this before running.** Nothing is persisted; credentials live
only for the single command invocation. To keep secrets out of the process list, shell history,
and this transcript:

- **Prefer `-E` (trusted auth)** whenever the user is on the box — then there is no secret at all.
- **Never accept a password as a slash-command argument** and **never place `-P <pass>` on the
  command line.** Both would be logged verbatim in the transcript.
- For SQL auth, pass the password via the **`SQLCMDPASSWORD` environment variable** set in the
  *same* shell invocation as sqlcmd (sqlcmd reads it automatically). Prompt the user for it with
  `Read-Host -AsSecureString` if it wasn't already provided out-of-band; never echo it back.

### 3. Run the audit
Invoke the single audit script and capture the pipe-delimited result set.

Trusted auth (preferred):
```
"<sqlcmd-path>" -S <server> -d <database> -E -C -N ^
  -i "${CLAUDE_PLUGIN_ROOT}/skills/sql-audit/queries/audit.sql" ^
  -s "|" -W -h -1 -w 65535
```

SQL auth — password via env var, **not** `-P` (PowerShell example; the env var is scoped to the
child process and cleared after):
```
$env:SQLCMDPASSWORD = (prompt securely)
try {
  & "<sqlcmd-path>" -S <server> -d <database> -U <user> -C -N `
    -i "${CLAUDE_PLUGIN_ROOT}/skills/sql-audit/queries/audit.sql" `
    -s "|" -W -h -1 -w 65535
} finally { Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue }
```

Flags: `-C` trust server cert, `-N` encrypt, `-s "|"` column separator, `-W` trim
whitespace, `-h -1` suppress headers, `-w 65535` wide rows. Each output line is:

```
severity|rule_id|rule_name|schema_name|object_name|detail
```

If sqlcmd errors on `STRING_AGG` (SQL Server < 2017), tell the user and re-run with the
`N06` and `D07` blocks commented out of a local copy of `audit.sql`, or note those two
rules as skipped.

### 4. Interpret findings
Parse the lines. For each `rule_id`, cross-reference `references/celko-rules.md` for the
rationale, book section, exceptions, and remediation. Remember the module-text rules
(`V01`, `C02`, `C03`, `C04`) are heuristic — if a finding looks like a false positive
(match inside a comment or string literal), inspect the object definition before
reporting it as a violation.

### 5. Emit the report
Write `audit-report.md` in the current working directory:

- **Summary**: counts by severity (ERROR / WARN / INFO) and total objects scanned.
- **Findings by severity**, then by rule. For each rule: the rule name, book section,
  one-line rationale, and a table of `schema.object` + `detail`.
- **Remediation notes** per rule (from `celko-rules.md`).
- Note any rules skipped (e.g. STRING_AGG-dependent rules on older engines) and any
  heuristic findings you set aside as false positives.

Severity meaning: **ERROR** = objective violation; **WARN** = deprecated / portability
risk; **INFO** = opinionated / Celko-preference (review, don't necessarily "fix").

## Reference files
- `references/celko-rules.md` — full rule catalog: rationale, exceptions, book citations, fixes.
- `references/sqlcmd-setup.md` — sqlcmd detection paths and install options.
- `queries/audit.sql` — the read-only audit script (one result set).
