---
name: sql-audit
description: Audit a SQL Server database for conformance to Joe Celko's SQL Programming Style. Use when the user wants to audit, lint, or review a SQL Server database schema, check naming conventions, find heap tables / missing primary keys, flag FLOAT/deprecated types, unnamed constraints, SELECT * views, optimizer hints, or generate a database style report. Connects via sqlcmd and produces a severity-tiered findings report.
---

# SQL Server Style Audit (Celko)

Audit a live SQL Server database against the rules distilled from *Joe Celko's SQL
Programming Style*. The audit is **read-only**: it queries the system catalog and
`sys.sql_modules` only — no data or schema is modified.

## Workflow

### 0. Setup mode (`--store`) — store a SQL password, no audit
If the invocation includes `--store <server> <user>`, this is first-time credential setup, not an
audit. **Do not run the audit.** The agent cannot prompt for a password (non-interactive shell), so
hand the user the exact command to run **themselves** (the `!` prefix runs it in their interactive
session, where the secure prompt works and the value stays out of the transcript):

```
! powershell -File "${CLAUDE_PLUGIN_ROOT}/scripts/credential.ps1" store -Server <server> -User <user>
```

Tell them it prompts securely and stores the password DPAPI-encrypted under
`sql-audit:<server>:<user>`, then they can run `/sql-audit <server> <database> -U <user>` and the
audit will pull it from the vault. Storage is per-machine (DPAPI doesn't roam), so this repeats
once on each new machine. Reference: `references/credential-manager.md`. Then stop.

### 1. Locate sqlcmd
Run the detector and capture the resolved path:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/detect-sqlcmd.ps1"
```

- Exit 0 → stdout is one JSON line:
  `{"path": "...", "flavor": "go-sqlcmd"|"odbc", "supportsContexts": true|false}`.
  Keep `path` to run sqlcmd. `supportsContexts` tells you whether reusable connection
  **contexts** are available (go-sqlcmd only — see step 2b).
- Exit 1 → sqlcmd is missing. **Show the printed guidance and ask the user** before
  installing anything. If they approve, run `winget install sqlcmd` (installs go-sqlcmd,
  which supports contexts), then re-run the detector. Do **not** auto-install without confirmation.

See `references/sqlcmd-setup.md` for probed locations/install details and
`references/contexts.md` for the full context lifecycle.

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
- **You (the agent) cannot prompt for a password.** The shell tools are non-interactive and don't
  persist state between calls, so a live `Read-Host` hangs, and anything the user types in chat is
  captured in the transcript. So for **SQL auth**, resolve the password from **Windows Credential
  Manager** (`scripts/credential.ps1`), read into `SQLCMDPASSWORD` for the single sqlcmd call:
    - If a credential exists, `scripts/credential.ps1 get -Server <s> -User <u>` returns it.
    - If not (or it errors "Element not found"), tell the user to store it once **themselves** via
      the `!` prefix (never in chat), then retry:
      `! powershell -File "${CLAUDE_PLUGIN_ROOT}/scripts/credential.ps1" store -Server <s> -User <u>`
    - See `references/credential-manager.md`. (go-sqlcmd contexts, step 2b, are an alternative.)

### 2b. Reusable connections with go-sqlcmd contexts (preferred for repeat audits)
Only when the detector reported `"supportsContexts": true`. A **context** is a named saved
connection, so the user picks a target once and SQL passwords are stored encrypted instead of
retyped. Full reference: `references/contexts.md`.

If the user asked for a context (e.g. `/sql-audit --context <name>`) or wants to reuse a
connection, list what exists and let them choose:
```
"<sqlcmd-path>" config get-contexts
```
Create one if none fits. Trusted (Windows) auth — no stored secret:
```
"<sqlcmd-path>" config add-endpoint --name <ep> --address <server> --port 1433
"<sqlcmd-path>" config add-context  --name <ctx> --endpoint <ep>
```
SQL auth — password taken from `SQLCMDPASSWORD` and stored **encrypted**:
```
$env:SQLCMDPASSWORD = (prompt securely)
try {
  "<sqlcmd-path>" config add-endpoint --name <ep> --address <server> --port 1433
  "<sqlcmd-path>" config add-user     --name <u>  --username <sqluser> --password-encryption dpapi
  "<sqlcmd-path>" config add-context  --name <ctx> --endpoint <ep> --user <u>
} finally { Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue }
```
**Always pass `--password-encryption dpapi` on Windows** — the default (`none`) stores the
password base64-encoded (effectively plaintext) in `%USERPROFILE%\.sqlcmd\sqlconfig`. Then run
the audit against the context (step 3, "Saved context").

If the detector reported `"supportsContexts": false` (classic ODBC sqlcmd) and the user wants
contexts, offer to install go-sqlcmd (`winget install sqlcmd`); otherwise use the per-run flow.

### 3. Run the audit
Invoke the single audit script and capture the pipe-delimited result set.

Trusted auth (preferred):
```
"<sqlcmd-path>" -S <server> -d <database> -E -C -N ^
  -i "${CLAUDE_PLUGIN_ROOT}/skills/sql-audit/queries/audit.sql" ^
  -s "|" -W -h -1 -w 65535
```

SQL auth — password pulled from Windows Credential Manager into the env var for one call, then
cleared (never `-P`, never typed in chat):
```
$env:SQLCMDPASSWORD = & "${CLAUDE_PLUGIN_ROOT}/scripts/credential.ps1" get -Server <server> -User <user>
try {
  & "<sqlcmd-path>" -S <server> -d <database> -U <user> -C -N `
    -i "${CLAUDE_PLUGIN_ROOT}/skills/sql-audit/queries/audit.sql" `
    -s "|" -W -h -1 -w 65535
} finally { Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue }
```
If `get` errors, the credential isn't stored yet — have the user store it via the `!` prefix
(see step 2). Reference: `references/credential-manager.md`.

Saved go-sqlcmd context (from step 2b) — no credentials on the command line, encrypted
password used automatically:
```
"<sqlcmd-path>" --context <ctx> -d <database> -C -N ^
  -i "${CLAUDE_PLUGIN_ROOT}/skills/sql-audit/queries/audit.sql" ^
  -s "|" -W -h -1 -w 65535
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
