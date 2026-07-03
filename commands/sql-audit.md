---
description: Audit a SQL Server database against Joe Celko's SQL Programming Style and write a tiered findings report.
argument-hint: --store <server> <user> | [server] [database] [-E | -U <user> | --context <name>]
---

Run a Celko-style audit of a SQL Server database.

Arguments (optional — ask for anything missing): `$ARGUMENTS`
- `--store <server> <user>` → **setup mode** (no audit): store this SQL login's password in
  Windows Credential Manager for later runs. See "Setup mode" below.
- first token → server (`-S`)
- second token → database (`-d`)
- auth: `-E` (trusted, preferred) or `-U <user>`
- `--context <name>` → use a saved **go-sqlcmd context** (server + encrypted credentials);
  then only the database is needed. If the flavor detected isn't go-sqlcmd, contexts are
  unavailable — offer to `winget install sqlcmd` or fall back to the per-run flow.

**Setup mode (`--store`).** When `--store` is present, do NOT run an audit. Parse the server and
user, then present the exact command for the user to run **themselves** (the agent cannot prompt
for a password — its shell is non-interactive):
`! powershell -File "${CLAUDE_PLUGIN_ROOT}/scripts/credential.ps1" store -Server <server> -User <user>`.
Explain it gives a secure prompt and stores the password DPAPI-encrypted under
`sql-audit:<server>:<user>`, then they can run `/sql-audit <server> <database> -U <user>`. Storage
is per-machine (DPAPI doesn't roam), so this one-time step repeats on each new machine.

**Do not accept a password in these arguments** — they are logged in the transcript. For SQL
auth (`-U <user>`), the skill resolves the password from **Windows Credential Manager** via
`scripts/credential.ps1 get` into the `SQLCMDPASSWORD` env var for a single sqlcmd call. If it
isn't stored yet, ask the user to store it once themselves (never in chat):
`! powershell -File "${CLAUDE_PLUGIN_ROOT}/scripts/credential.ps1" store -Server <s> -User <u>`.
Prefer `-E` (trusted auth) when possible. `--context <name>` uses a saved go-sqlcmd context
instead. Credentials at rest are DPAPI-encrypted; the command line never carries a password.

Use the **sql-audit** skill. Steps:
1. Run `scripts/detect-sqlcmd.ps1` to locate sqlcmd; if missing, show its guidance and
   ask before installing go-sqlcmd (`winget install sqlcmd`).
2. Confirm server / database / auth with the user.
3. Execute `skills/sql-audit/queries/audit.sql` via sqlcmd (pipe-delimited, headerless).
4. Cross-reference `skills/sql-audit/references/celko-rules.md` and write `audit-report.md`
   grouped by severity (ERROR / WARN / INFO) with rule name, book section, rationale,
   affected objects, and remediation.

The audit is strictly read-only.
