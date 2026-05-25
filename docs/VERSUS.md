# Versus match tracking

bizzymod-stats tracks Versus / Realism Versus / Scavenge play at four
granularities, recorded automatically by the plugin:

```
match            ── one campaign play with stable teams
  └─ match_map   ── one map within that match
      └─ match_round (×2) ── one half (Survivors + Infected swap between)
            └─ player_round_stats (×N) ── per-player breakdown of that half
```

Plus a long-running per-player rollup: `player_versus_stats`.

## The vocabulary

- **Match** — one *contiguous* campaign play. Starts on the first map of
  a campaign in a versus mode; ends on `versus_match_finished` (finale
  played out), campaign change, mode change, or server restart
  (abandoned). Two teams, stable identity, accumulated score across all
  maps.
- **Match map** — one map within the match. Two rounds (halves) make a
  map. The map winner is whichever team scored higher *as Survivors*
  across the two halves combined.
- **Round (a.k.a. half)** — what L4D2 internally calls a "round." One
  team plays Survivors, the other plays Infected. The engine
  side-swaps every half via the team-flip mechanic.
- **Team letter** — `'A'` or `'B'`. Stable across the engine side-swap;
  only changes when a player voluntarily switches teams via
  `jointeam`. At match start, whoever's on Survivors in round 1 is **A**.
  This maps onto the engine's `m_iCampaignScore[0]/[1]` indices, which
  are also stable across the swap.

## What the schema holds

| Table                 | Granularity | Notable columns |
|-----------------------|-------------|-----------------|
| `matches`             | 1 per match | `team_a_score`, `team_b_score`, `winner` ENUM('A','B','draw','abandoned'), `end_reason` |
| `match_teams`         | 2 per match | `final_score`, `rounds_won`, `rounds_lost`, `maps_won`, `maps_lost` |
| `match_team_players`  | N per team  | `joined_round`, `left_round`, `time_on_team_s` — composite PK includes `joined_round` so voluntary swap creates a new row |
| `match_maps`          | N per match | `ordinal` (1..N), `team_a_score`, `team_b_score`, `winner` ENUM('A','B','draw','incomplete') |
| `match_rounds`        | 2 per map   | `round_index` (1 or 2), `survivor_team` ('A' or 'B'), **`engine_score`** + **`plugin_score_surv`** + **`plugin_score_inf`**, `end_reason` |
| `player_round_stats`  | N per round | `points`, `kills`, `deaths`, `incaps`, `damage_*`, `awards_count`, `side` (2=surv/3=inf), `team_letter` |
| `player_versus_stats` | 1 per (player, gamemode) | `matches_won/lost/drawn/abandoned`, `rounds_won/lost`, `rounds_as_surv/inf`, `current_win_streak`, `longest_win_streak`, … |

## Two scores per round, not one

Each `match_rounds` row stores two distinct scores for the Survivor team's
half:

- **`engine_score`** — what the L4D2 engine itself reports via the
  `terror_player_manager.m_iCampaignScore` netprop. This is the
  *authoritative* score the game uses to decide the map winner —
  distance-based, factoring in saferoom bonuses, survivor health, etc.
  This is what your players are arguing about when they say "we won."
- **`plugin_score_surv` / `plugin_score_inf`** — what bizzymod-stats
  accumulated for that team's players during the round, sum of all
  `Bizzy_Score()` calls. This is our PPM-feeding metric, useful for MVP
  analysis and "who was carrying," but it's not what the game uses to
  decide the winner.

The `winner` ENUM is derived from `engine_score` (not the plugin score),
which means the bizzymod-stats `winner` column matches what players actually
saw on the scoreboard at the end of the map.

If a custom engine build doesn't expose `m_iCampaignScore`, `engine_score`
falls back to 0 and the map winner is decided by `plugin_score_surv`
instead. There's no silent loss — the engine-score-zero rows are
identifiable and can be reprocessed if you ever want to backfill.

## The team-letter problem

L4D2's only persistent "which side are you on" identifier is the
m_iCampaignScore *array index* — `[0]` and `[1]` stick to two opposing
team identities across the side swap. SourcePawn doesn't expose any
direct `GetClientPersistentTeam()`. The plugin therefore maintains
`g_PlayerTeam[client]` as a `'A'`/`'B'` letter, assigned on first-sight
and only changed on voluntary `jointeam` (detected via the `player_team`
event firing while a round is active — engine flips happen between rounds,
when `g_RoundIndex == 0`).

Late joiners get a letter based on the side they joined into and the
current round's `survivor_team`. They get a `match_team_players` row with
`joined_round` = current round index so analysis queries can distinguish
"played the whole match" from "joined in round 5."

Voluntary swaps close one membership row (`left_round = current`) and
open a new one for the opposite letter. A player's contribution to a
match is therefore the union of all their `match_team_players` rows for
that match.

## Win/loss accounting

On match close (`versus_match_finished`, campaign change, mode change,
plugin shutdown):

1. `matches.winner` set from cumulative `team_a_score` vs `team_b_score`.
2. `match_teams.final_score` updated for both letters.
3. For every player who has any `match_team_players` row, a row is
   upserted into `player_versus_stats`:
   - `matches_played++`
   - `matches_won++` / `matches_lost++` / `matches_drawn++` /
     `matches_abandoned++` based on outcome and their team_letter
   - `current_win_streak` / `current_loss_streak` updated atomically,
     with `longest_*` raised via `GREATEST()`
   - Per-round counters (`rounds_played`, `rounds_won/lost`,
     `rounds_as_surv/inf`, `total_round_score_*`) aggregated from
     `player_round_stats` joined to `match_rounds` for this match

The streak math runs inside the SQL UPSERT so it stays correct even if
multiple matches close concurrently (improbable, but defensive). If a
team is marked `abandoned`, no win/loss is recorded against any roster
player — only `matches_abandoned++`.

## Useful queries

```sql
-- Best win-rate (min 10 matches)
SELECT name, gamemode, match_winrate_pct, matches_played
FROM v_player_versus
WHERE matches_played >= 10
ORDER BY match_winrate_pct DESC
LIMIT 20;

-- Longest active win streaks
SELECT name, gamemode, current_win_streak, longest_win_streak
FROM v_player_versus
ORDER BY current_win_streak DESC
LIMIT 20;

-- Per-round MVP for a given match
SELECT mr.round_index, mr.survivor_team,
       CAST(p.name AS CHAR) AS player, prs.team_letter, prs.side,
       prs.points, prs.kills, prs.damage_dealt
FROM player_round_stats prs
JOIN match_rounds mr ON mr.id = prs.match_round_id
JOIN players p ON p.id = prs.player_id
WHERE mr.match_id = 42
ORDER BY mr.round_index, prs.points DESC;

-- "Was team A ahead at this point in the match?" — running score by map
SELECT ordinal,
       SUM(team_a_score) OVER (ORDER BY ordinal) AS running_a,
       SUM(team_b_score) OVER (ORDER BY ordinal) AS running_b
FROM match_maps
WHERE match_id = 42
ORDER BY ordinal;
```

## Known limitations and extension points

- **Engine score fallback to plugin score** when the netprop isn't
  exposed (custom engine builds). Documented above.
- **Plugin restart mid-match** marks the match as `abandoned`. Resumption
  across plugin reload would require persisting the `g_PlayerTeam[]`
  mapping; not implemented because team identity is only correct if the
  same players are still connected, which is rarely true after a restart.
- **Scavenge round counting** uses the same code path. The `round_index`
  in scavenge corresponds to scavenge halves, not individual scavenge
  rounds-within-a-half. Per-can-pour granularity inside a scavenge half
  is a future extension via `gascan_pour_completed` event tracking — the
  schema already supports it through `player_round_stats.awards_count`.
- **Spectator team transitions** during a round don't trigger a letter
  change (they just stop accumulating, since `g_RoundClients[i].side`
  goes to 1=spectator and `CloseRound` filters non-team-2/3 sides). A
  spectator who later rejoins a team gets re-assigned correctly.

## See also

- [`STATS.md`](STATS.md) — what stats are tracked plugin-wide
- [`DATABASE.md`](DATABASE.md) — overall schema tour
- `plugin/scripting/bizzymod_stats/versus.sp` — the implementation
- `schema/migrations/mysql/006_versus_rounds.sql` — the tables
