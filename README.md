# hosca-plugins

A [Claude Code](https://code.claude.com/docs/en/plugins) plugin **marketplace** for database and
SQL Server tooling.

## Plugins

| Plugin | Description |
|--------|-------------|
| [**sql-audit-skill**](plugins/sql-audit-skill) | Audit a SQL Server database against Joe Celko's *SQL Programming Style* — read-only catalog queries via `sqlcmd`, severity-tiered findings report. |

## Install

```
/plugin marketplace add ehosca/hosca-plugins
/plugin install sql-audit-skill@hosca-plugins
```

The first command registers this marketplace; the second installs the plugin (invokable as
`/sql-audit`). See each plugin's README for usage.

## Maintainers

Versioning and release process: [`RELEASING.md`](RELEASING.md). Changelog:
[`CHANGELOG.md`](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
