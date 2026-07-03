# sqlcmd Setup

The audit runs `queries/audit.sql` through `sqlcmd`. `scripts/detect-sqlcmd.ps1` locates
an existing install; if none is found it prints guidance and exits non-zero.

## Probe order (detect-sqlcmd.ps1)
1. **PATH** — `Get-Command sqlcmd`.
2. **go-sqlcmd via winget** — `%LOCALAPPDATA%\Microsoft\WinGet\Links\sqlcmd.exe`.
3. **Bundled ODBC/SSMS/VS tools** — `…\Microsoft SQL Server\Client SDK\ODBC\<ver>\Tools\Binn\SQLCMD.EXE`
   under both `%ProgramFiles%` and `%ProgramFiles(x86)%`, highest `<ver>` first. This is where
   SSMS, Visual Studio, and the Microsoft ODBC Driver install the classic `sqlcmd`.

## If not found — install (ask the user first)
Open-source **go-sqlcmd** (recommended, cross-platform):
```
winget install sqlcmd
```
Or grab a release binary: https://github.com/microsoft/go-sqlcmd/releases

`sqlcmd` also arrives with SSMS, Visual Studio, or the standalone
**Microsoft ODBC Driver for SQL Server** + **sqlcmd** MSI.

After installing, re-run the detector.

## Invocation
Trusted auth (preferred). For SQL auth, add `-U <user>` and pass the password via the
`SQLCMDPASSWORD` env var — **not** `-P` (see [Credentials](#credentials--connection-info)).
```
"<sqlcmd-path>" -S <server> -d <database> -E -C -N ^
  -i "<plugin>/skills/sql-audit/queries/audit.sql" ^
  -s "|" -W -h -1 -w 65535
```
| Flag | Purpose |
|------|---------|
| `-S` | server (`localhost`, `localhost\SQLEXPRESS`, `tcp:host,1433`) |
| `-d` | database to audit |
| `-E` | trusted (Windows) auth |
| `-U` | SQL login (password via `SQLCMDPASSWORD` env var, never `-P`) |
| `-C` | trust server certificate |
| `-N` | encrypt connection |
| `-s "|"` | column separator for parsing |
| `-W` | trim trailing whitespace |
| `-h -1` | suppress column headers |
| `-w 65535` | wide output (avoid wrapping) |

## Credentials & connection info

Nothing is persisted by default — connection parameters live only for a single run.

| Item | Where it lives | Notes |
|------|----------------|-------|
| Server, database | command args or prompt | non-secret; may be defaulted (see below) |
| Trusted auth (`-E`) | n/a | **preferred** — no credential handled at all |
| SQL username (`-U`) | command args or prompt | non-secret |
| SQL password | **Windows Credential Manager** (DPAPI), read into `SQLCMDPASSWORD` at run time | **never** `-P` on the command line, **never** a slash-command argument, **never** typed in chat |

**Preferred: Windows Credential Manager.** Store the password once (DPAPI-encrypted, user-scoped);
the audit reads it into `SQLCMDPASSWORD` for a single sqlcmd call. Works with classic ODBC sqlcmd
— no go-sqlcmd needed. Full flow in [`credential-manager.md`](credential-manager.md).

```powershell
# one-time store (secure prompt):
powershell -File scripts/credential.ps1 store -Server <srv> -User <user>
# at audit time:
$env:SQLCMDPASSWORD = & scripts/credential.ps1 get -Server <srv> -User <user>
try   { & sqlcmd -S <srv> -d <db> -U <user> -C -N -i audit.sql -s "|" -W -h -1 }
finally { Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue }
```

sqlcmd (classic ODBC and go-sqlcmd) reads **`SQLCMDPASSWORD`** automatically, so the secret stays
out of `argv`, shell history, and the transcript.

**Optional persistence (repeat audits).** If the detected binary is **go-sqlcmd**
(`"supportsContexts": true`), save a named **context** instead of retyping — endpoint + user are
stored in `%USERPROFILE%\.sqlcmd\sqlconfig`, with the SQL password **encrypted** when created with
`--password-encryption dpapi` (Windows). Then run `sqlcmd --context <name> -d <db> -i audit.sql`.
See [`contexts.md`](contexts.md) for the full lifecycle. Alternatively keep only **non-secret**
defaults (server, database) in a plugin-local `.claude/sql-audit-skill.local.md` — never the
password. Both are opt-in; the default flow stores nothing.

## Permissions
The audit reads catalog views and `sys.sql_modules`. The login needs `VIEW DEFINITION`
on the target database (or membership giving it) so module text is visible for the
view/module rules (V01, C02–C04); otherwise those definitions read as NULL and are skipped.

## Engine version note
Rules **N06** and **D07** use `STRING_AGG` (SQL Server 2017+). On older engines sqlcmd will
error on those blocks — comment them out of a local copy of `audit.sql` or note them as skipped.

## go-sqlcmd differences
go-sqlcmd honors `-C`/`-N` for encryption/cert trust (often required against default TLS
settings). Behavior of `-s`, `-W`, `-h`, `-w` matches the classic ODBC `sqlcmd`.
