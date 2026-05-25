# ConVars

All ConVars are registered in `plugin/scripting/bizzymod_stats/config.sp`. The
default config is auto-exec'd from `cfg/sourcemod/bizzymod_stats.cfg`; an
example lives at `plugin/configs/bizzymod_stats.cfg.example`.

| ConVar | Default | Range | Purpose |
|--------|---------|-------|---------|
| `bizzymod_stats_version` | (auto) | — | Plugin version (read-only, set on register) |
| `bizzymod_stats_enabled` | `1` | 0–1 | Master switch. 0 disables all stat collection. |
| `bizzymod_stats_announce_join` | `1` | 0–1 | Print joining player's rank/points to chat. |
| `bizzymod_stats_announce_rank` | `1` | 0–1 | Announce when a player's rank changes. |
| `bizzymod_stats_ffire_mode` | `1` | 0–2 | Friendly fire scoring: 0=off, 1=cooldown, 2=damage-based. |
| `bizzymod_stats_ffire_multiplier` | `1.5` | ≥0 | Damage-mode multiplier: penalty = damage × multiplier. |
| `bizzymod_stats_ffire_cooldown` | `10.0` | ≥0 | Seconds between counted FF incidents (cooldown mode). |
| `bizzymod_stats_difficulty_multiplier` | `1` | 0–1 | Apply difficulty multipliers to scoring. |
| `bizzymod_stats_negative_score` | `1` | 0–1 | Allow point losses (negative scoring events). |
| `bizzymod_stats_log_events` | `0` | 0–1 | Write `award_events` firehose for activity feeds. |
| `bizzymod_stats_bot_multiplier` | `1.0` | ≥0 | Multiplier on bot-related penalties (0 disables). |

## Legacy aliases

The legacy plugin's `bizzymod_stats_*` ConVars are **not** registered. If your
existing server config references them, rename to the `bizzymod_stats_*`
equivalents or maintain a shim file. The semantics are the same.

## Per-event tunables

Award-firing event handlers in `events.sp` query CVars opportunistically
via the `GetCV("bizzymod_stats_<name>", default)` helper. These are *not*
pre-registered — adding `bizzymod_stats_witch_kill 30` to your config takes
effect immediately without a plugin change. Names follow this pattern:

| Name | Used in | Default |
|------|---------|---------|
| `bizzymod_stats_survivor_incap` | infected scoring (incap) | 15 |
| `bizzymod_stats_survivor_death` | infected scoring (kill) | 40 |
| `bizzymod_stats_witch_kill` | survivor witch kill | 20 |
| `bizzymod_stats_common_kill` | common infected kill | 1 |
| `bizzymod_stats_pounce_perfect_damage` | hunter pounce award threshold | 25 |
| `bizzymod_stats_pounce_nice_damage` | hunter pounce award threshold | 15 |
| `bizzymod_stats_scatter_ram_hits` | charger scattering-ram threshold | 4 |
| `bizzymod_stats_burn` | zombie ignited (per kill point) | 1 |
| `bizzymod_stats_log_si_spawns` | write `si_spawn_records` per-spawn rows | 0 |
| `bizzymod_stats_lone_threshold` | distance for "alone" classification (units) | 750 |
| `bizzymod_stats_bw_threshold` | HP below which player is in BW state | 40 |
| `bizzymod_stats_multikill_window_ms` | ms window for multi-kill burst detection | 150 |
| `bizzymod_stats_kill_assist_window_s` | seconds before kill that count as an assist | 5 |
| `bizzymod_stats_chain_revive_window_s` | seconds for chain-revive linkage | 60 |
| `bizzymod_stats_ff_kill_window_s` | seconds within which FF damage credits a kill | 10 |
| `bizzymod_stats_heal_other` | medkit used on teammate | 10 |
| `bizzymod_stats_ff_base_penalty` | cooldown-mode FF penalty per incident | 25 |

These are intentionally CV-driven (not hardcoded) so server operators can
tune the meta without recompiling. Document new ones here when you add
them in `events.sp`.
