# bizzymod-stats — stats reference (for the website)

Everything the website can surface. All stats live in the shared **`bizzymod_stats`**
MySQL database (connection is the `bizzymod_stats` block in each server's
`databases.cfg`). Read from the **views** below rather than raw tables — views are the
stable, documented surface; raw tables are implementation detail and may change.

Per-server attribution: rows carry a `server_id` where relevant (246 = Bizzy's Dugout,
218 = Campaign; Flat's Hole has its own id). The `players` table keys on `id`
(= `player_id` in every view); join `players p ON p.id = v.player_id` for names/steamids.

## The versus outcome tiers (important)
A versus match nests four decision levels. The site can show win/loss at each:

| Tier | What it is | Where |
|---|---|---|
| **Round / half** | one survivor run (a team on Survivors). No individual winner — it's a score. | `match_rounds`, `player_round_stats` |
| **Map / chapter** | one map = both halves; winner = higher survivor score. This is what players call "a round of versus". | `match_maps.winner`; per-player `maps_won`/`maps_lost` in `v_player_versus` |
| **Penultimate** | who was ahead **going into the finale** (finale excluded). Most comp matches are decided here. | `v_match_penultimate`, `v_player_penultimate` |
| **Mini-game** | a decided result for matches that **never reached the finale** (abandoned/short). | `v_match_minigame`, `v_player_minigame` |
| **Match / campaign** | cumulative survivor-score lead across the whole campaign. | `matches.winner`, `v_match_summary`, `v_player_versus` |

Scoring at every level is **cumulative survivor points** (`SUM(match_rounds.plugin_score_surv)` per `survivor_team`).

## Player leaderboards

| View | Rows | What it exposes |
|---|---|---|
| `v_player_totals` | populated | All-time per-player totals: points, playtime, kills, headshots, shots, deaths, damage, points/min, accuracy %, headshot %. |
| `v_top_players` | populated | Same shape as `v_player_totals`, trimmed to the leaderboard. |
| `v_player_versus` | populated | **Per-player versus record**: matches played/won/lost/drawn/abandoned, round (= map) W/L, maps W/L, rounds as surv/inf, win/loss streaks, `match_winrate_pct`, `round_winrate_pct`. |
| `v_player_penultimate` | populated | **NEW.** Per-player penultimate W/L/draw + `penult_winrate_pct` (finale-reaching matches). |
| `v_player_minigame` | populated | **NEW.** Per-player mini-game W/L/draw + `mini_winrate_pct` (non-finale matches). |
| `v_player_ties` | populated | **NEW.** Per-player draw counts across every level: `map_draws`, `penultimate_draws`, `minigame_draws`, `match_draws`. |
| `v_side_preference` | populated | Per-player, per team-letter (A/B): matches, wins, losses, `winrate_pct`. |
| `v_player_precision` | populated | Accuracy: shots fired/hit, head/chest/limb damage, `accuracy_pct`, `headshot_pct`. |
| `v_player_ttk` | populated | Time-to-kill per SI type: count, min/max/avg ms. |
| `v_si_skill` | populated | SI performance per type: spawns, kills/incaps caused, best signature, avg damage, kill rate. |
| `v_player_health` | populated | Health discipline: avg HP at saferoom/pills/medkit, hoarding counts. |
| `v_career_bests` | populated | Single-event records per player (most points/kills in a round, biggest pounce/punch, longest streak, etc.). |
| `v_player_awards_summary` | populated | Award counts per player per award code. |

## Match & map detail

| View | Rows | What it exposes |
|---|---|---|
| `v_match_summary` | populated | Per-match: server, gamemode, campaign, start/end, maps/rounds played, team scores, `winner`, `end_reason`. |
| `v_match_penultimate` | populated | **NEW.** Penultimate `a_pts`/`b_pts`, `margin`, `penultimate_winner`, `final_winner`, `finale_flipped` (did the finale change the result). Only matches that reached the finale. |
| `v_match_minigame` | populated | **NEW.** For matches that never reached the finale: `a_pts`/`b_pts`, `margin`, `halves_played`, `minigame_winner`, `end_reason`. |
| `v_match_score_curve` | populated | Running team scores map-by-map (for a score-progression chart). |
| `v_match_comebacks` | populated | Per-match max lead each side + `is_comeback` flag. |
| `v_match_team_roster` | populated | Who was on which team (A/B) per match, with join/leave round + time on team. |
| `v_map_summary` | populated | Per-map: campaign, is_finale, plays, playtime, survivor vs infected wins. |
| `v_tank_summary` | populated | Tank fights: survival, distance, incaps/kills caused, outcome, controller, killer, weapon. |
| `v_crescendo_stats` | sparse | Crescendo encounters: cleared/wiped/avg duration. |

## Helpers / reference (used by the views above; not usually surfaced directly)
`finale_maps` (official finale map codes), `v_match_reached_finale`, `v_match_prefinale_scores`.

## Not populated yet — do NOT surface
These views exist but their source events aren't being captured, so they're empty:
`v_player_character_pref`, `v_revive_chains`, `v_saferoom_order`, `v_tank_contributors`.

## Notes for the site
- **`reached_finale`** is based on whether the finale **map's stats were recorded**, which can
  differ from `matches.end_reason = 'finale'` if the finale chapter wasn't captured. Such a match
  appears under mini-games, not penultimate (its result is still the pre-finale standing).
- Win-rates are computed over **decided** games (`wins / (wins + losses)`), excluding draws and abandons.
- Negative survivor cumulative scores are clamped to 0 in `matches.team_a_score`/`team_b_score`, but
  the **winner** is computed from the raw (un-clamped) totals — so read the winner column, not the
  clamped score columns, when you need the result.
