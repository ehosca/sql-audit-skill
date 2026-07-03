# SQL Auth via Windows Credential Manager

The **preferred** way to supply a SQL Server password. The secret is stored once in Windows
Credential Manager (generic credential, user-scoped, **DPAPI-encrypted at rest**) and read at
audit time into the `SQLCMDPASSWORD` environment variable for a single sqlcmd call — it never
appears on the command line, in shell history, or in the Claude Code transcript.

`scripts/credential.ps1` wraps the Win32 `CredWrite`/`CredRead`/`CredDelete` APIs via P/Invoke —
no third-party PowerShell modules.

## Why Credential Manager (vs. a file or env var)

- **Works with the sqlcmd you already have.** Unlike go-sqlcmd *contexts*, this needs no
  go-sqlcmd — it drives the classic ODBC `sqlcmd` too (sqlcmd reads `SQLCMDPASSWORD` natively).
- **Same encryption class as a DPAPI context** (both are user-scoped DPAPI) but centrally
  managed and revocable via Control Panel → Credential Manager, with no loose config file.
- sqlcmd has **no** native "read from Credential Manager" mode, so the helper bridges the vault
  to `SQLCMDPASSWORD`. The plaintext exists only in the process memory of the single sqlcmd call.

Target-name scheme: **`sql-audit:<server>:<user>`**.

## Store (one-time — run it yourself, not through the agent)

The agent's shell tools are non-interactive, so it cannot prompt for a password (a live
`Read-Host` would hang) and must never receive one via chat. Store it yourself with the `!`
prefix so the value stays local:

```
! powershell -File "<plugin>/scripts/credential.ps1" store -Server db.example.com -User auditor
```

You get a secure `Read-Host` prompt; the password is written straight to the vault. Nothing is
echoed.

## Use (what the skill runs)

```powershell
$env:SQLCMDPASSWORD = & "<plugin>/scripts/credential.ps1" get -Server db.example.com -User auditor
try {
    & sqlcmd -S db.example.com -d MyDatabase -U auditor -C -N `
        -i "<plugin>/skills/sql-audit/queries/audit.sql" -s "|" -W -h -1 -w 65535
}
finally { Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue }
```

`get` prints only the password to stdout for capture; run it in the *same* shell as sqlcmd (tool
shells don't share state between calls) and never log its output.

## List / rotate / delete

```
powershell -File credential.ps1 list                                   # target names only (no secrets)
! powershell -File credential.ps1 store  -Server <s> -User <u>          # rotate = store again
powershell -File credential.ps1 delete -Server <s> -User <u>            # remove
```

`list` uses `cmdkey /list` under the hood, which by design never reveals stored passwords.

## Notes

- Persistence is `CRED_PERSIST_LOCAL_MACHINE` — available to the user across sessions on this
  machine; it does not roam.
- DPAPI ties the secret to the current Windows user; another user (or another machine) cannot
  read it.
- Prefer trusted auth (`-E`) when you're on the box — then there is no secret to store at all.
- go-sqlcmd contexts remain a valid alternative when go-sqlcmd is installed
  (see [`contexts.md`](contexts.md)).
