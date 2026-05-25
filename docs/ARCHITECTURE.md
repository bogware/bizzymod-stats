# Architecture

```
   ┌────────────────────┐   game events     ┌────────────────────────┐
   │  L4D / L4D2 server │ ─────────────────▶│  bizzymod-stats plugin     │
   │   + SourceMod      │                   │  (modular SourcePawn)  │
   └────────────────────┘                   └──────────┬─────────────┘
                                                       │ async writes
                                                       │ (Database / Transaction API)
                                                       ▼
                                            ┌────────────────────────┐
                                            │   MySQL 8 (bizzymod_stats)   │
                                            │  normalized schema +   │
                                            │  catalogs + views      │
                                            └──────────┬─────────────┘
                                                       │ reads
                                                       ▼
                                            ┌────────────────────────┐
                                            │   web (PHP 8 + PDO)    │
                                            │   stub leaderboards    │
                                            └────────────────────────┘
```

## Plugin

Single SourceMod plugin (`bizzymod_stats.smx`) compiled from a multi-file
SourcePawn project under `plugin/scripting/`. The main file
`bizzymod_stats.sp` only orchestrates — every concern lives in a sub-module
under `plugin/scripting/bizzymod_stats/`:

| Module          | Role |
|-----------------|------|
| `util.sp`       | Pure helpers (no global state writes) |
| `config.sp`     | ConVar registration |
| `database.sp`   | Async DB connection + write queue / transactions |
| `identity.sp`   | Resolve/create `servers`, `players`, `maps`, `weapons` rows; cache IDs in memory |
| `session.sp`    | Per-player session lifecycle (open on auth, flush on disconnect/map end) |
| `scoring.sp`    | Central `Bizzy_Score()` — single point where multipliers and the negative-score CVAR apply |
| `awards.sp`     | Data-driven award firing (codes resolved via the `awards` catalog) |
| `weapons.sp`    | Per-weapon stat capture; auto-extends the `weapons` catalog |
| `events.sp`     | All `HookEvent` registrations — the bridge from engine events to scoring/awards |
| `timedmaps.sp`  | Map duration tracking (shortest for most modes, longest for Survival) |
| `rankvote.sp`   | Vote to shuffle teams by PPM (`sm_rankvote` / `sm_rank_shuffle`) |
| `motd.sp`       | MOTD storage in `kv_settings`, `sm_showmotd` / `sm_rank_motd` |
| `commands.sp`   | Player commands (`sm_rank`, `sm_top10`, `sm_top10ppm`, `sm_nextrank`, menu, mute) |
| `versus.sp`     | Match / round / team tracking for versus modes (see [VERSUS.md](VERSUS.md)) |
| `combat.sp`     | Combat granularity — per-victim damage log, kill assists, multi-kills, hitgroup routing, DPS, BW state, FF-kills-caused |
| `tank_witch.sp` | Per-tank-spawn (`tank_records`) and per-witch-encounter (`witch_records`) bookkeeping |
| `movement.sp`   | 0.25s position sampler — distance, time-alone, team spread, BW polling |
| `coordination.sp` | Revive chains, save-of-save, crescendo events, finale waves |

### Hot-path discipline

- **No blocking SQL.** Every write goes through `Bizzy_DB_Exec()` or
  `Bizzy_DB_BeginTxn()` / `Bizzy_DB_RunTxn()`. Reads go through
  `Bizzy_DB_Query()` with a callback. The game tick is never blocked.
- **Counters live in memory.** `g_Clients[client].*` accumulates per
  session; one transaction flushes the deltas to `player_stats` on
  disconnect or map end. This drops round-trip count by 100×+ vs the
  legacy plugin's per-event writes.
- **String escaping is mandatory.** All untrusted strings (player names,
  weapon classnames, MOTD) go through `Bizzy_DB_Escape()` before being
  formatted into SQL. Never `Format("%s", untrusted)`.

### Lifecycle

```
OnPluginStart
  ├─ detect game (L4D1/L4D2) — SetFailState if neither
  ├─ register CVARs                          (config.sp)
  ├─ AutoExecConfig
  ├─ Bizzy_OnDatabaseInit                    (database.sp)
  │   └─ Database.Connect("bizzymod_stats")
  │       └─ OnDBConnected
  │           └─ Bizzy_Identity_EnsureServer (identity.sp)
  │               └─ resolve g_ServerId, then replay any already-connected clients
  ├─ HookEvent registrations                 (events.sp)
  └─ admin menu hookup (optional)

OnClientPostAdminCheck
  └─ Bizzy_BeginClientSession
      └─ Bizzy_Identity_ResolvePlayer       (upsert + lookup, async)
          └─ Bizzy_Session_Open             (INSERT sessions row)

OnClientDisconnect
  └─ Bizzy_EndClientSession
      └─ Bizzy_Session_Flush                (one transaction: UPSERT player_stats, close session, touch players)
```

## Schema

See [`DATABASE.md`](DATABASE.md). Two principles drive every design choice:

1. **Catalogs as data, not columns.** The legacy `players` table had
   ~80 columns; here, awards / weapons / SI / gamemodes / difficulties
   are catalog tables, and stats are keyed by their numeric IDs in
   `player_stats`, `player_si_stats`, `player_awards`,
   `player_weapon_stats`. Adding a new award or weapon is an INSERT, not
   an `ALTER TABLE`.

2. **One row per dimension combination.** `player_stats` is keyed by
   `(player_id, gamemode_id, difficulty_id, server_id)`. Rolling up
   across difficulties is a `SUM()`; per-mode top-10 is `WHERE
   gamemode_id = ?`. Views in `005_views.sql` provide the common rollups.

## Web

The web tier is intentionally a stub. It uses only `v_player_totals`,
`v_top_players`, and a handful of direct table reads. No write paths,
no auth, no caching — its purpose is to demonstrate that the schema is
queryable from a normal app, not to be a finished product. Refinement
will follow once the plugin + schema stabilize.
