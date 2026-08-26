# Changelog

All notable changes to bizzymod-stats are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); we use SemVer.

## [Unreleased]

### Fixed

- **Negative session score dropped the whole stat flush (#7).** A player who
  ended a session with negative points (griefing / friendly fire, with
  `negative_score` on) produced a negative `most_points_in_session`, but that
  column is `INT UNSIGNED` — MySQL rejected the row with "Out of range value",
  which failed the career-bests query and rolled back the entire
  `Bizzy_Session_Flush` transaction, losing that session's stats. Clamp the
  inserted value with `GREATEST(0, …)`; a negative career "best" is meaningless.

## [0.6.0] — 2026-05-25

**First public release.** Built from scratch over a 2026-Q2 sprint as a
modern rewrite of "Custom Player Stats" v1.5 (preserved under `legacy/`).

### Added — Schema

14 numbered MySQL 8 migrations, all additive and idempotent, totalling
**62 tables/views + 82 awards + 8 survivors catalog**:

- **001 init schema** — catalogs (`games`, `gamemodes`, `difficulties`,
  `special_infected`, `weapons`), identity (`servers`, `players`, `maps`),
  `sessions`, `player_settings`, `kv_settings`, `schema_migrations`.
- **002 stat tables** — `player_stats` (the big one), `player_si_stats`,
  `player_weapon_stats`, `map_stats`, `map_plays`, `timed_maps`.
- **003 awards** — data-driven awards catalog + `player_awards` +
  `award_events` firehose.
- **004 seed catalogs** — initial games, gamemodes, difficulties, SIs,
  ~40 weapons, ~30 awards.
- **005 views** — `v_top_players`, `v_player_totals`,
  `v_player_awards_summary`, `v_map_summary`.
- **006 versus rounds** — full match → map → round → per-player MVP
  hierarchy. Tables: `matches`, `match_teams`, `match_team_players`,
  `match_maps`, `match_rounds`, `player_round_stats`,
  `player_versus_stats`. Views: `v_match_summary`,
  `v_match_team_roster`, `v_player_versus`.
- **007 extended stats** — throwables, target-specific damage, time
  alive/dead/incapped, pinned-by-SI counts, distance, `career_bests`
  table, +8 awards.
- **008 combat granularity** — hitgroup breakdown, kill assists,
  multi-kills (2/3/4/5+), DPS peak, long-distance kills, BW damage,
  environment/self damage, fall deaths, FF-kills-caused, reloads, +8
  awards. Views: `v_player_ttk`, `v_player_precision`.
- **009 SI micro-stats** — per-SI deep columns: smoker drag distance +
  self-clears, hunter pounce flight + skeeted, boomer death-pop + vomit
  range, spitter cone, jockey ride distance, charger straight-line +
  ledge throws, tank survival/distance/handoffs, witch crown attempts.
  `si_spawn_records` granular log. View: `v_si_skill`. +8 awards.
- **010 health & inventory** — HP-at-event snapshots (saferoom, pills,
  adrenaline, medkit), BW state tracking, hoarded items, defib target
  points, weapon-tier time, lowest-HP-survival. View: `v_player_health`.
  +6 awards.
- **011 movement & positioning** — distance, time-alone, team spread,
  fall damage, `saferoom_arrivals` table. View: `v_saferoom_order`.
  +6 awards.
- **012 coordination** — `revive_events` (with chain detection),
  `boss_damage_log`. Views: `v_revive_chains`, `v_tank_contributors`.
  +4 awards.
- **013 round-shaping events** — `tank_records` (per-tank-spawn cards),
  `witch_records`, `crescendo_events`, `finale_waves`, per-round
  attribution counters. Views: `v_tank_summary`, `v_crescendo_stats`.
  +7 awards.
- **014 versus deep-dive** — SI death-cause breakdown,
  `survivors` catalog (Bill/Francis/Louis/Zoey + Nick/Coach/Ellis/Rochelle),
  `player_character_stats`, `scavenge_gascans`, `director_placements`,
  mercy/health bonus columns. Views: `v_player_character_pref`,
  `v_match_score_curve`, `v_match_comebacks`, `v_side_preference`.
  +4 awards.

### Added — Plugin (modular SourceMod 1.12 SourcePawn)

`bizzymod_stats.smx` (~60 KB binary) compiled from a multi-file project
under `plugin/scripting/`:

| Module | Role |
|--------|------|
| `bizzymod_stats.sp` | Entry point; orchestrates module init |
| `util.sp` | Helpers (no global state writes) |
| `config.sp` | ConVar registration |
| `database.sp` | Async MySQL connection + write queue / transactions |
| `identity.sp` | Servers, players, maps resolution + ID caching |
| `session.sp` | Session lifecycle + 6-UPSERT transactional flush |
| `scoring.sp` | Central `Bizzy_Score()` (the single point-mutation API) |
| `awards.sp` | Catalog-driven award firing |
| `weapons.sp` | Per-weapon shot/hit/kill/headshot capture |
| `events.sp` | ~50 game event hooks, the integration layer |
| `combat.sp` | Hitgroup routing, kill assists, multi-kill burst detection, DPS rolling-window peak, BW state polling, FF-kills-caused tracker |
| `tank_witch.sp` | Per-tank-spawn (`tank_records`) and per-witch-encounter (`witch_records`) management with `boss_damage_log` writes |
| `movement.sp` | 4 Hz position sampler — distance, time-alone, team spread, weapon-tier time, tank-position deltas |
| `coordination.sp` | Revive chain detection, save-of-save credit, crescendo/finale-wave lifecycle |
| `versus.sp` | Match/round/team tracking with side-swap-stable team letters and engine-score capture |
| `timedmaps.sp` | Per-map best-time tracking |
| `rankvote.sp` | Vote-based team shuffle by PPM |
| `motd.sp` | MOTD storage + display |
| `commands.sp` | Player + admin commands |

**Async DB I/O only.** Every write goes through
`Bizzy_DB_Exec()` / `Bizzy_DB_BeginTxn()`. No SQL ever blocks the game
tick. String escaping via `Bizzy_DB_Escape()` is mandatory before any
dynamic SQL.

### Added — CI/CD

- **Self-hosted GitHub Actions** workflows under `.github/workflows/`.
- `tests/run.sh` — bash test harness exercising compile + 14 migration
  applies + idempotency + 7 catalog seed checks + 3 FK rejection probes
  + 8 view selectability. Auto-downloads the SM 1.12 toolchain on first
  run.
- `.github/runner-setup.sh` — idempotent runner-prereq installer.
- `docs/CI.md` — full self-hosted runner setup guide.

### Added — Web stub (PHP 8 / PDO)

`web/` directory with `index.php` (top players), `matches.php`,
`match.php?id=`, `player.php?id=`, `awards.php`, `server.php`. Reads
views only; no write paths. Intentionally minimal — exists to prove
the schema is queryable; production-grade UI is on the roadmap.

### Added — Documentation

- `README.md` — full operator manual
- `docs/ARCHITECTURE.md` — how the three components interact
- `docs/DATABASE.md` — schema tour
- `docs/STATS.md` — every captured stat with source event + DB column
- `docs/VERSUS.md` — match/round/team-letter design deep-dive
- `docs/CVARS.md` — ConVar reference
- `docs/CI.md` — self-hosted CI setup
- `docs/INSTALL.md` — install walkthrough
- `docs/RELEASE.md` — release process
- `docs/ROADMAP.md` — what's still on the wishlist

### Fixed — Bugs caught during the v0.6.0 review pass

- **`Bizzy_Session_Flush` now writes all ~70 in-memory counters** across
  6 transactional UPSERTs against `player_stats` + 1 UPSERT against
  `career_bests`. Previously only ~25 counters (migrations 001-007's
  columns) reached the DB; everything from 008-013 was tracked in memory
  but never persisted. **This was the biggest bug.**
- **`Bizzy_OnMapEnd` reset is now complete** via a new
  `ResetSessionCounters()` helper. Multi-map sessions used to double-
  count stats; now they don't.
- **`versus_round_start` / `scavenge_round_start` event mode** corrected
  from `PostNoCopy` to `Post`. The handler reads `is_secondary_round`
  from the event, which would have failed silently under PostNoCopy.
- **Movement sampler quarter-second over-count** fixed:
  `time_alone_s` and `weapon_t*_time_s` columns now divide by 4 at
  flush time (sampler accumulates at 4 Hz, columns are seconds).
- **Per-weapon `shots_fired` decoupled from per-hit**. Now
  `Event_WeaponFire` calls `Bizzy_Weapons_RecordShot()` for per-shot
  count, and `Bizzy_Weapons_RecordHit()` only counts hits.
  Previously `shots_fired` was counted per hit, so accuracy stats were
  meaningless.
- **`scoring.sp` null-guards** added around `FindConVar(...).IntValue`
  for `bizzymod_stats_survivor_death` and `bizzymod_stats_ff_base_penalty`
  — previously could crash if the CVar wasn't registered.
- **Tank-punch tracking** now requires victim to be a Survivor — the
  previous code incremented `punches_landed` and `damageToTank` for
  any damage event regardless of victim team.
- **Crescendo incap counter** now wired from `Event_PlayerIncap` —
  previously `survivors_down` always stayed at 0 in `crescendo_events`.
- **Dead code removed** — `(void)x;` placeholders, empty `if` bodies
  with nonsensical conditions, unused `g_CrescendoStartIncaps` /
  `g_CrescendoStartDeaths` state variables.

### Known limitations (deferred to 0.7.0)

- **`avg_team_spread_units`** column not written — schema stores a
  single value but plugin tracks sum+count. Needs a sum/samples
  schema split. The `max_team_spread_units` is correctly written and
  is the more useful metric anyway.
- **`mostRevivesThisSession` / `mostHealsThisSession`** declared in
  `ClientState` but never incremented. The capture wiring is the
  outstanding work; the columns and reset logic are in place.
- **Tank `rocks_thrown`** column never incremented (no `tank_throw`
  event hook yet). `rocks_hit` is captured via `Bizzy_TankWitch_TankRockHit`
  but the event wiring needs to be added.
- **`Bizzy_Coord_WaveStart` / `WaveFinish`** declared but no event
  drives them — `finale_waves` table stays empty in 0.6.0. Wiring
  needs `finale_vehicle_*` event hooks.
- **`time_leading_s` / `time_trailing_s` / `time_dead_s` / `time_incapped_s`**
  columns exist with reset logic but no capture wiring yet. These need
  map-progress awareness (Left4DHooks) or an incap-state poller.
- **Per-character (Bill/Nick/etc.) capture** — `survivors` catalog and
  `player_character_stats` table seeded; plugin doesn't yet write to
  `player_character_stats` (needs survivor-model classifier).
- **`si_spawn_records`** table exists for granular per-spawn logging;
  plugin doesn't yet write to it (controlled by a future
  `bizzymod_stats_log_si_spawns` CVar).
- **L4D1 parity** — plugin loads on L4D1 and the schema supports it,
  but several SI micro-stats (jockey, charger, spitter, scavenge) are
  L4D2-only. L4D1 captures the core (kills, headshots, damage, awards,
  campaigns) but not the L4D2-flavored extras.

### Compatibility

- Targets **SourceMod 1.12** (`spcomp64`).
- **L4D2** is the focus and is fully tested. **L4D1** works for the
  L4D1-applicable subset.
- **MySQL 8.0** is the primary target; MySQL 5.7+ works with utf8mb4.

### Credits

Based on "Custom Player Stats" v1.5 by Mikko Andersson (muukis),
derived from earlier work by msleeper. Original under GPLv3 on
AlliedModders; bizzymod-stats continues under GPLv3.

[0.6.0]: https://github.com/bogware/bizzymod-stats/releases/tag/v0.6.0
