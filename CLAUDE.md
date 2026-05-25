# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`bizzymod-stats` v2 — a modernized rewrite of the 2010-era "Custom Player Stats"
SourceMod plugin for Left 4 Dead 1 / Left 4 Dead 2. Three coordinated
components share one MySQL database:

- **`plugin/`** — modern, modular SourcePawn plugin (one `.sp` entry +
  `bizzymod_stats/*.sp` modules). Async DB I/O only; per-session counter
  aggregation; data-driven awards/weapons.
- **`schema/`** — MySQL 8 normalized schema delivered as numbered,
  idempotent migrations. Python migration runner.
- **`web/`** — PHP 8 + PDO stub front-end. Intentionally minimal — exists
  to prove the schema is queryable. Refinement deferred.
- **`legacy/`** — the original 2015 codebase, preserved untouched. Never
  edit; reference only.

## Common commands

```bash
# Build the plugin (requires sourceknight + spcomp; see sourceknight.yaml)
sourceknight build

# Apply DB migrations
cd schema/scripts && pip install -r requirements.txt
python migrate.py --host 127.0.0.1 --user root --database bizzymod_stats

# Run the web stub
cd web && cp config.example.php config.php
php -S 127.0.0.1:8080 -t public
```

CI (`.github/workflows/ci.yml`) builds the plugin on every push/PR and
validates migrations against a MySQL 8 service container, including an
idempotency re-run check and a catalog-seed smoke test.

Release (`.github/workflows/release.yml`) fires on `v*` tags: builds,
stages an `addons/sourcemod/...` tree plus `schema/`, zips it, and
attaches to a GitHub Release with auto-generated changelog.

## Plugin architecture (the part most likely to need editing)

**Multi-file SourcePawn plugin.** `plugin/scripting/bizzymod_stats.sp` is the
entry — it `#include`s every module under `plugin/scripting/bizzymod_stats/`
and orchestrates init order in `OnPluginStart`. Shared symbols
(globals, enums, the `ClientState` struct, forward declarations of each
module's `Bizzy_On*Init`) live in `plugin/scripting/include/bizzymod_stats.inc`.

**Modules and what they own** — see `docs/ARCHITECTURE.md` for the full
table. Key non-obvious ones:

- `database.sp` — **every** DB call goes through `Bizzy_DB_Exec()` /
  `Bizzy_DB_Query()` / `Bizzy_DB_BeginTxn()` + `Bizzy_DB_RunTxn()`. Never
  call `g_DB.Query` directly from a module; the wrappers handle the
  null-DB case and standardize error logging.
- `scoring.sp` — **every** point mutation goes through `Bizzy_Score()`.
  It's the single place that applies the difficulty multiplier, the
  `bizzymod_stats_negative_score` gate, and the `award_events` firehose.
  Modules calling raw integer math against `g_Clients[client].pointsThisSession`
  is a bug.
- `identity.sp` — `g_ServerId`, `g_Clients[i].playerId`, `g_CurrentMapId`,
  and `g_AwardIds` / `g_WeaponIds` (StringMaps) are all caches populated
  from async lookups. Any code path that uses them must be prepared for
  the zero/missing case (the typical pattern is a `DataPack` queued
  callback that retries on `g_AwardIds.Size == 0`).
- `session.sp` — **the only place that writes `player_stats`.** Other
  modules accumulate in `g_Clients[i].*` and `Bizzy_Session_Flush()`
  emits one UPSERT per disconnect/map-end. If you add a new rollup
  column, you must extend the `INSERT … ON DUPLICATE KEY UPDATE`
  statement there too — otherwise the in-memory counter never reaches
  the DB.
- `versus.sp` — **owns a second, parallel counter bank** `g_RoundClients[]`
  scoped to a single round. Every `Bizzy_Score` / `Bizzy_RecordKill` /
  `Bizzy_RecordDamage` / `Bizzy_Awards_Fire` mirrors into round counters
  via `Bizzy_Versus_Accum*()` helpers; round counters flush to
  `player_round_stats` at `round_end` and zero out. If you add a new
  per-round metric, add a column to `player_round_stats` (migration 006+),
  a field to the `RoundClient` struct, an `AccumXxx` call at the
  capture site, and an entry in the `CloseRound` flush SQL.

**Hot-path discipline:**
- No blocking SQL. Ever.
- String escape with `Bizzy_DB_Escape()` before any `Format("%s", ...)`
  into SQL — player names and weapon classnames are untrusted.
- Counters accumulate in memory; flush in batched transactions.

## Schema landmines

- **Catalog IDs are stable contracts.** `gamemodes.id`, `difficulties.id`,
  `special_infected.id`, `awards.id` are referenced by integer in the
  plugin's enums (`include/bizzymod_stats.inc`). Migrations may **add** rows;
  renumbering existing rows is a hard break. New gamemodes/awards get
  appended IDs (see `holdout=7`, `tankrun=8`).
- **Migrations are forward-only and additive.** The runner records
  sha256 of each applied file and warns on drift but does not roll
  back. Breaking changes bump the plugin major version.
- **`server_id = 0`** in `player_stats` and `player_awards` means "rolled
  up across all servers." The plugin currently writes to `server_id=0`
  only; per-server breakdown is a query-time `GROUP BY`. Per-server
  rows in `player_stats` are reserved for a future cross-server
  dashboard.
- **Views are recreated** by `005_views.sql` on every apply (they're
  DROP+CREATE, not tracked). If you add or change a view, do it in 005
  or a later `00X_views_*` file with the same DROP+CREATE idiom.

## Cross-component contracts

- The plugin looks up a `databases.cfg` entry named literally **`bizzymod_stats`**
  (`BIZZY_DB_CONFIG_NAME` in `include/bizzymod_stats.inc`). Don't rename
  without updating the constant.
- The plugin persists its server identity in
  `cfg/sourcemod/bizzymod_stats.server_key` (a 32-hex random token, generated
  on first run). Deleting that file creates a new `servers` row on next
  start — old stats are not lost, but new ones land under a new
  `server_id`. Don't delete it casually.
- The web tier reads only views and direct rollup tables. It never
  writes. If you add a write path, justify it in the PR.

## What to consult, when

- Editing the plugin → `docs/ARCHITECTURE.md` (modules + lifecycle) and
  `docs/STATS.md` (the full event-to-column map; also lists extension
  points for stats that have a column but no hook yet).
- Editing the schema → `docs/DATABASE.md` (tables + why-normalized).
- Adding a CVar → `docs/CVARS.md` (registered vs lazy `GetCV` patterns).
- Cutting a release → `docs/RELEASE.md`.
- Touching versus / round / match tracking → `docs/VERSUS.md` (the
  vocabulary, the team-letter problem, why there are two scores per
  round, useful queries).

## `legacy/`

The pre-rewrite codebase. `legacy/bizzymod_stats.sp.v1.5` is 339 KB of
old-syntax SourcePawn; `legacy/l4d2stats.legacy.sql` is a 200 KB Navicat
dump with the wide-column schema described in `docs/DATABASE.md`'s "why
normalized" section; `legacy/web/` is the 2013 PHP frontend with
deprecated `mysql_*` calls. Read it when you need to confirm the
historical scoring formula or CVar semantics; do not port code from it
verbatim — it predates `methodmap`, `Database` API, and prepared
statements.
