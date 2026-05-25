# Database

MySQL 8 (also runs on 5.7+ at utf8mb4). The schema is delivered as
numbered, idempotent migrations under `schema/migrations/mysql/`.

## Migration runner

```
python schema/scripts/migrate.py \
  --host 127.0.0.1 --user root --password X --database bizzymod_stats
```

The runner:

- Creates `schema_migrations` if missing.
- Sorts files by their `NNN_` prefix and applies any not yet recorded.
- Records the sha256 of each applied file. On re-run, files whose
  checksum has changed since application emit a **warning** (the runner
  does not attempt to re-apply or repair them; correcting drift is a
  manual / forward-migration concern).

## Tables at a glance

### Catalogs (mostly static; seeded by migration 004)

| Table              | Purpose |
|--------------------|---------|
| `games`            | L4D1 / L4D2 |
| `gamemodes`        | Coop, Versus, Realism, Survival, Scavenge, … |
| `difficulties`     | Easy / Normal / Advanced / Expert (+ multiplier) |
| `special_infected` | Smoker, Boomer, Hunter, Spitter, Jockey, Charger, Witch, Tank |
| `weapons`          | Canonical L4D1/L4D2 weapon classnames; auto-extended at runtime |
| `awards`           | Award catalog (Witch Crowner, Bulldozer, Friendly Fire, etc.) |

### Identity

| Table              | Purpose |
|--------------------|---------|
| `servers`          | One row per reporting game server (keyed by a stable random token) |
| `players`          | Identity + last-seen metadata; stats live elsewhere |
| `maps`             | Map catalog (auto-extended on first sight of an unknown map) |
| `player_settings`  | KV per-player preferences (`mute`, etc.) |
| `kv_settings`      | Global KV store; replaces legacy `server_settings` |

### Rollup stats (the heart of the schema)

| Table                | Key                                                        | Stores |
|----------------------|------------------------------------------------------------|--------|
| `player_stats`       | `(player_id, gamemode_id, difficulty_id, server_id)`       | core counters: points, playtime, kills, accuracy, damage, FF, rescues, finale flow |
| `player_si_stats`    | `(player_id, gamemode_id, si_id)`                          | per-SI counters: pounces, vomits, rides, impacts, scattering rams, bulldozers, tank punches |
| `player_weapon_stats`| `(player_id, weapon_id)`                                   | per-weapon shots/hits/kills/headshots/damage |
| `player_awards`      | `(player_id, award_id, gamemode_id)`                       | award counts, first/last earned |
| `map_stats`          | `(map_id, gamemode_id, difficulty_id)`                     | per-map rollups |

### Event-grained (optional, off by default)

| Table          | When written |
|----------------|--------------|
| `sessions`     | Always — one row per (player, server) connect..disconnect |
| `map_plays`    | When `bizzymod_stats_log_events=1` — per-play log for time-series analysis |
| `award_events` | When `bizzymod_stats_log_events=1` — firehose for activity-feed UIs |
| `timed_maps`   | Always — best (or longest, for Survival) per (player, map, mode, difficulty) |

### Versus / Realism Versus / Scavenge (always-on when in a versus mode)

See [`VERSUS.md`](VERSUS.md) for the full design. Quick reference:

| Table                 | Granularity                  | Drives |
|-----------------------|------------------------------|--------|
| `matches`             | 1 per campaign play          | "we just played" cards, leaderboards |
| `match_teams`         | 2 per match (letters A/B)    | per-team final scores + rounds_won/lost |
| `match_team_players`  | rosters (incl. mid-match join/leave) | who was on which team |
| `match_maps`          | 1 per map within a match     | per-map winner with both team scores |
| `match_rounds`        | 2 per map (the halves)       | **engine_score** (authoritative) + plugin_score_surv/inf, end_reason |
| `player_round_stats`  | per-player per-half          | MVP-of-round, per-half drill-down |
| `player_versus_stats` | per (player, gamemode)       | match/round win rate, win/loss streaks |

### Views (recreated by migration 005)

| View                       | What |
|----------------------------|------|
| `v_player_totals`          | One row per player; sums across modes/difficulties/servers; computes PPM, accuracy %, headshot % |
| `v_top_players`            | `v_player_totals` filtered to `playtime_s >= 1800`, ordered by points desc — the leaderboard |
| `v_player_awards_summary`  | Per-player award totals with names |
| `v_map_summary`            | Per-map rollup across difficulties |
| `v_match_summary`          | One row per match: server, gamemode, campaign, both team scores, winner |
| `v_match_team_roster`      | Who was on each team of each match |
| `v_player_versus`          | Per-player versus stats with computed match/round win-rate % |

## Why normalized

The legacy `players` table had ~80 columns including `points_survivors`,
`points_infected`, `points_scavenge_survivors`, `points_realism_versus`,
`infected_spawn_1`..`infected_spawn_8`, and an `award_*` column for every
single award. Every new gamemode or award required an `ALTER TABLE` and
matching plugin code changes in two places (the column definition and the
`DB_PLAYERS_TOTALPOINTS` SQL fragment baked into the plugin).

In the new schema, adding a new award is one INSERT into `awards`. Adding
a new gamemode is one INSERT into `gamemodes`. Tracking a new per-weapon
stat is one ALTER on `player_weapon_stats` — no plugin column-list changes
required. Top-N queries that used to need 11-term SUM expressions become
`ORDER BY points DESC LIMIT N` against `player_stats` or the view.

## Catalog ID stability

The IDs in `gamemodes`, `difficulties`, and `special_infected` match the
legacy plugin's `GAMEMODE_*` / `INF_ID_*` defines wherever they did not
conflict between L4D1 and L4D2. New IDs (`holdout=7`, `tankrun=8`) are
appended. **Do not renumber existing catalog rows** — the plugin's enums
in `plugin/scripting/include/bizzymod_stats.inc` rely on them.
