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
```
"<sqlcmd-path>" -S <server> -d <database> {-E | -U <user> -P <pass>} -C -N ^
  -i "<plugin>/skills/sql-audit/queries/audit.sql" ^
  -s "|" -W -h -1 -w 65535
```
| Flag | Purpose |
|------|---------|
| `-S` | server (`localhost`, `localhost\SQLEXPRESS`, `tcp:host,1433`) |
| `-d` | database to audit |
| `-E` | trusted (Windows) auth |
| `-U` / `-P` | SQL login / password |
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
| SQL password | `SQLCMDPASSWORD` env var, set in the same shell call | **never** `-P` on the command line, **never** a slash-command argument (both are logged to the transcript / visible in the process list) |

sqlcmd (classic ODBC and go-sqlcmd) reads **`SQLCMDPASSWORD`** automatically, so the secret stays
out of `argv`, shell history, and the transcript. Scope it to the child process and clear it after:

```powershell
$env:SQLCMDPASSWORD = (Read-Host 'SQL password' -AsSecureString | ConvertFrom-SecureString -AsPlainText)
try   { & sqlcmd -S <srv> -d <db> -U <user> -C -N -i audit.sql -s "|" -W -h -1 }
finally { Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue }
```

**Optional persistence (repeat audits).** If you audit the same server often, use go-sqlcmd
*contexts* instead of retyping — `sqlcmd config add-endpoint` / `add-context` store the endpoint
(and, on supported builds, an encrypted password) in `%USERPROFILE%\.sqlcmd\sqlconfig`; then run
`sqlcmd --context <name> -d <db> -i audit.sql`. Alternatively, keep only **non-secret** defaults
(server, database) in a plugin-local settings file `.claude/sql-audit-skill.local.md` in the
consuming project — never put the password there. Both are opt-in; the default flow stores nothing.

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
