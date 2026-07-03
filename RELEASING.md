# Releasing

Maintainer guide for cutting releases of the **hosca-plugins** marketplace and its plugins. Users
don't need this — see [`README.md`](README.md) to install.

## Versioning model

Two independent version streams, both [SemVer](https://semver.org/):

- **Each plugin** is versioned by the `version` field in its own
  `plugins/<name>/.claude-plugin/plugin.json`. This is the single source of truth for that plugin.
- **The marketplace catalog** is versioned by the top-level `version` in
  [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json). Bump it when the catalog
  itself changes — a plugin added, removed, or renamed, or a marketplace-manifest structure change —
  not when a plugin's internals change.

Bump plugin versions by impact: **MAJOR** for breaking changes, **MINOR** for
backward-compatible features, **PATCH** for fixes.

### Why the `version` field matters

Claude Code only ships a plugin update to existing users when the resolved version *changes*.
Version resolution order is:

1. `version` in the plugin's `plugin.json`
2. `version` in the plugin's `marketplace.json` entry
3. the git commit SHA of the plugin's source

Because `plugin.json` wins, **do not also set `version` in the plugin's `marketplace.json` entry** —
a stale value there would be silently masked by `plugin.json` (or worse, mask it if you ever removed
the `plugin.json` field). Keep `plugin.json` as the only place a plugin declares its version.

Consequence: pushing new commits without bumping `plugin.json` `version` does **nothing** for
existing users — Claude Code sees the same version string and keeps the cached copy. Bump on every
user-facing release. (Omitting `version` entirely would instead treat every commit SHA as a new
version — we don't do that here; we pin explicit versions.)

## Git tag convention

- **Plugin release:** `<plugin-name>--v<version>` — e.g. `sql-audit-skill--v0.1.0`. This is the
  `{plugin-name}--v{version}` form Claude Code's plugin-dependency pinning expects, so tags stay
  forward-compatible with dependency version constraints.
- **Marketplace catalog release:** `v<version>` — e.g. `v0.1.0`.

## Per-release checklist

For a **plugin** release:

1. Bump `version` in `plugins/<name>/.claude-plugin/plugin.json`.
2. In that plugin's `CHANGELOG.md`, move the `[Unreleased]` entries under a new
   `## [<version>] - <YYYY-MM-DD>` heading.
3. Commit (e.g. `Release sql-audit-skill 0.2.0`).
4. Tag: `git tag sql-audit-skill--v<version>`.
5. `git push && git push --tags`.

For a **marketplace** release (catalog change):

1. Bump the top-level `version` in `.claude-plugin/marketplace.json`.
2. Move `[Unreleased]` entries in the root [`CHANGELOG.md`](CHANGELOG.md) under a new dated heading.
3. Commit, then tag `v<version>`, then push with `--tags`.

A plugin change and a catalog change can land in the same release — just bump and tag both.

## Validate before tagging

```
claude plugin validate .
claude plugin validate ./plugins/sql-audit-skill
```
