# Tests

A small regression fixture that proves the audit rules actually fire on real objects.
[`fixtures/scratch-schema.sql`](fixtures/scratch-schema.sql) builds an isolated
`SqlAuditTest` database whose objects deliberately violate a known set of rules — the six
that don't naturally occur in the AdventureWorks sample (D01, D03, D04, N07, V01, C03),
plus incidental hits that confirm D06/D07/N06.

## Run

```powershell
$sqlcmd = "<sqlcmd-path>"            # e.g. from scripts/detect-sqlcmd.ps1
$srv    = "localhost\SQLEXPRESS"

# 1. build the fixture
& $sqlcmd -S $srv -E -C -N -i tests/fixtures/scratch-schema.sql

# 2. run the real audit against it
& $sqlcmd -S $srv -d SqlAuditTest -E -C -N `
    -i skills/sql-audit/queries/audit.sql -s "|" -W -h -1 -w 65535

# 3. tear it down
& $sqlcmd -S $srv -E -C -N -Q "ALTER DATABASE SqlAuditTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE SqlAuditTest;"
```

## Expected findings

Each fixture object maps to the rule(s) it is designed to trip:

| Object | Rule | Sev | Why |
|--------|------|-----|-----|
| `bad_heap` | **D01** | ERROR | no PRIMARY KEY |
| `float_col_tbl.measure_amt` | **D04** | ERROR | `float` column |
| `legacy_join_proc` | **C03** | WARN | `*=` in module text (in a comment — heuristic) |
| `v_select_star` | **V01** | WARN | `SELECT *` in view |
| `guid_key.customer_ref` | **D03** | INFO | `uniqueidentifier` PK |
| `generic_id.id` | **N07** | INFO | generic `id` PK |

Incidental (also correct): **D06** on each auto-named PK, **D07** and **N06** on the
unconstrained / unpostfixed numeric columns (`some_col`, `row_id`, `id`, `customer_ref`).

D06 lines reference auto-generated constraint names (e.g. `PK__generic___3213E83F…`);
the hash suffix varies per run, so match on rule/object rather than byte-for-byte.

These six plus the twelve that fire on AdventureWorks exercise all 18 rules.
