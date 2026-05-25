# Stats captured

This is what the plugin records, where it ends up in the DB, and which
game event drives it. Use this as a checklist when adding a new stat.

## Combat (survivor side)

| Stat                              | Source event                  | DB column |
|-----------------------------------|-------------------------------|-----------|
| Shots fired                       | `weapon_fire`                 | `player_stats.shots_fired` + `player_weapon_stats.shots_fired` |
| Shots hit                         | `player_hurt` (attacker)      | `player_stats.shots_hit` + `player_weapon_stats.shots_hit` |
| Damage dealt                      | `player_hurt` (attacker)      | `player_stats.damage_dealt` + `player_weapon_stats.damage_dealt` |
| Damage taken                      | `player_hurt` (victim)        | `player_stats.damage_taken` |
| Headshot kills                    | `player_death` w/ `headshot`  | `player_stats.headshots` + `player_weapon_stats.headshots` |
| Common infected kills             | `infected_death`              | `player_stats.kills_common` |
| Special infected kills            | `player_death` (vt=infected)  | `player_stats.kills_special` |
| Tank kills                        | `tank_killed`                 | `player_stats.kills_tank` + award `tank_kill` |
| Tank kill — no survivor deaths    | `tank_killed` w/ `solo`       | award `tank_kill_no_deaths` |
| Witch kills                       | `witch_killed`                | `player_stats.kills_witch` |
| Witch crowner (one-shot kill)     | `witch_killed` w/ `oneshot`   | award `witch_crowned` |
| Witch disturbed                   | `witch_harasser_set`          | award `witch_disturb` |
| Melee kills                       | `player_death` w/ melee weapon| `player_stats.kills_melee` |

## Combat (infected side)

| Stat                              | Source event                       | DB |
|-----------------------------------|------------------------------------|----|
| Survivor kills                    | `player_death` (kt=infected)       | `player_stats.kills_survivor` |
| Survivor incaps                   | `player_incapacitated`             | `player_stats.incaps` |
| Hunter pounces                    | `lunge_pounce`                     | `player_si_stats.hunter_pounces` |
| Perfect pounce (≥25 damage)       | `lunge_pounce` w/ `damage`         | `player_si_stats.hunter_perfect_pounces` + award |
| Nice pounce (≥15 damage)          | `lunge_pounce` w/ `damage`         | `player_si_stats.hunter_nice_pounces` + award |
| Hunter pounce damage              | `lunge_pounce`                     | `player_si_stats.hunter_pounce_damage` |
| Smoker pulls                      | _events.sp extension point_        | `player_si_stats.smoker_pulls` |
| Smoker choke damage               | _events.sp extension point_        | `player_si_stats.smoker_choke_damage` |
| Boomer perfect vomit (4 hits)     | `player_hurt` x4 from one boom     | `player_si_stats.boomer_perfect_vomits` + award |
| Jockey rides                      | `jockey_ride`                      | `player_si_stats.jockey_rides` |
| Jockey ride duration              | `jockey_ride_end`                  | `player_si_stats.jockey_ride_time_s` |
| Charger impacts                   | `charger_impact`                   | `player_si_stats.charger_impacts` |
| Scattering Ram (≥4 impacts)       | `charger_impact` w/ `hits`         | award `scattering_ram` |
| Tank punches                      | _events.sp extension point_        | `player_si_stats.tank_punches` |
| Bulldozer (≥200 damage punch)     | `player_hurt` filter on tank punch | award `bulldozer` |
| Tank rocks thrown / hit           | _events.sp extension point_        | `player_si_stats.tank_rocks_*` |
| Tank Sniper (rock hit)            | `player_hurt` w/ thrown rock       | award `tank_sniper` |
| Spitter spit damage               | _events.sp extension point_        | `player_si_stats.spitter_pool_damage` |

## Survivor support

| Stat                              | Source event                       | DB |
|-----------------------------------|------------------------------------|----|
| Revives                           | `revive_success`                   | `player_stats.revives` + award `revive` |
| Defib uses                        | `defibrillator_used`               | `player_stats.defibs_used` + award `defib` |
| Pills shared                      | `pills_used` (giver != patient)    | `player_stats.pills_given` + award `pills_shared` |
| Adrenaline shared                 | `adrenaline_used` (giver != patient)| `player_stats.adrenaline_given` + award `adrenaline_shared` |
| Medkit used on other              | `heal_success` (healer != patient) | `player_stats.medkits_used_on_other` |
| Gas can poured                    | `gascan_pour_completed`            | `player_stats.gascans_poured` + award `gas_pour` |
| Gas can pour interrupted          | _events.sp extension point_        | `player_stats.gascans_partial` |
| Ammo upgrade deployed             | `upgrade_pack_used`                | `player_stats.ammo_upgrades_deployed` + award `ammo_upgrade` |
| Saved from SI pin                 | `pounce_stopped` + analogues       | `player_stats.saved_from_*` + award `protect` |
| Car alarm triggered (penalty)     | `triggered_car_alarm`              | `player_stats.caralarms_triggered` + award `caralarm_triggered` |

## Round / game flow

| Stat                              | Source event                       | DB |
|-----------------------------------|------------------------------------|----|
| Map completed                     | `map_transition`                   | `player_stats.maps_completed` + award `all_in_safehouse` |
| Campaign finished                 | `finale_win`                       | `player_stats.campaigns_finished` + award `campaign` |
| Last survivor on finale           | _events.sp extension point_        | award `left4dead` |
| Round win (versus/scavenge)       | `round_end`                        | `player_stats.wins` (+ infected award) |
| Mission lost                      | `mission_lost`                     | `player_stats.losses` |
| Map timing (single-team modes)    | `OnMapStart` / `mission_*`         | `timed_maps.best_time_ms` |

## Discipline (negative)

| Stat                              | Source event                       | DB |
|-----------------------------------|------------------------------------|----|
| Friendly fire incidents           | `player_hurt` w/ same team         | `player_stats.ff_incidents` + award `friendly_fire` |
| Friendly damage dealt             | `player_hurt` w/ same team         | `player_stats.damage_friendly` |
| Friendly incaps                   | `player_incapacitated` same team   | award `friendly_incap` |
| Teamkills                         | `player_death` same team           | `player_stats.teamkills` + award `teamkill` |

## Versus match / round tracking

Captured automatically when the active gamemode is Versus, Realism
Versus, or Scavenge — independent of (and in addition to) the rollup
counters above. See [`VERSUS.md`](VERSUS.md) for the full design.

| Stat                                    | Source                              | DB |
|-----------------------------------------|-------------------------------------|----|
| Match start                             | `OnMapStart` in versus mode         | `matches` (new row) |
| Match end (finale)                      | `versus_match_finished`             | `matches.ended_at`, `winner` |
| Match end (abandoned)                   | mode change / plugin shutdown       | `matches.winner='abandoned'` |
| Round (half) start                      | `versus_round_start`/`scavenge_round_start` | `match_rounds` (new row) |
| Round end (engine winner + scenario score) | `round_end` + `m_iCampaignScore` netprop | `match_rounds.engine_score`, `end_reason` |
| Per-player round breakdown              | `round_end` flush of round counters | `player_round_stats` |
| Per-map winner across 2 halves          | computed at 2nd `round_end`         | `match_maps.winner` |
| Team A/B identity across side-swap      | plugin-side `g_PlayerTeam[]` map    | `match_team_players` |
| Voluntary team swap mid-match           | `player_team` during active round   | new `match_team_players` row |
| Tank / Witch appeared this round        | `tank_spawn` / `witch_spawn`        | `match_rounds.tank_appeared/witch_appeared` |
| Per-player versus rollups               | match close                         | `player_versus_stats` (matches/rounds/streaks) |

## Section 1-7 (migrations 008-014) captures

The roadmap §1-§7 are fully implemented as of migration 014. New
modules in the plugin: `combat.sp` (combat granularity), `tank_witch.sp`
(per-tank-spawn / per-witch-encounter records), `movement.sp` (4 Hz
position sampler), `coordination.sp` (revive chains, crescendos, finale
waves).

### Combat granularity (mig 008 / combat.sp)

| Stat                        | Source | DB |
|-----------------------------|--------|----|
| Damage by hitbox            | `player_hurt.hitgroup` → `Bizzy_Combat_RouteHitgroup()` | `player_stats.dmg_hitgroup_*` + `player_weapon_stats.dmg_head/chest/limb` |
| Multi-kills per shot        | `infected_death` burst window (150ms) | `player_stats.multikill_2/3/4/5plus` + awards |
| Kill assists (SI/tank/witch) | per-victim damage log + 5s window | `player_stats.kill_assists_special/tank/witch` |
| Tank solo kill (≥50% dmg)   | boss damage log aggregation | `player_stats.tank_solo_kills` |
| DPS peak (5s rolling)       | sliding window on damage events | `career_bests.peak_dps` |
| Long-distance kill          | position delta at kill time | `career_bests.longest_kill_units` |
| Biggest single hit          | per-`player_hurt` peak tracker | `career_bests.biggest_single_hit` |
| BW state damage taken       | HP<40 check on `player_hurt` (victim) | `player_stats.damage_taken_bw`, `bw_entries`, `bw_time_s` |
| Environment damage taken    | weapon=='world'/'worldspawn' filter | `player_stats.damage_environment` |
| Self damage                 | attacker==victim filter | `player_stats.damage_self` |
| Fall deaths                 | `player_death` with weapon=='world' | `player_stats.fall_deaths` |
| FF kills caused             | FF damage + death within 10s | `player_stats.ff_kills_caused` + award `ff_killer` |
| Reloads                     | `weapon_reload` event | `player_stats.reloads` + `player_weapon_stats.reloads` |

### SI micro-stats (mig 009)

All on `player_si_stats`. The relevance varies by SI; the columns are
documented inline in the migration. Headline ones:

| SI       | Notable columns |
|----------|-----------------|
| Smoker   | `smoker_drag_total_units`, `smoker_max_drag_units`, `smoker_self_clears`, `smoker_choke_time_s`, `smoker_tongue_attempts` |
| Hunter   | `hunter_pounce_total_units`, `hunter_pounce_max_units`, `hunter_pounce_total_time_ms`, `hunter_pounce_skeeted` |
| Boomer   | `boomer_vomit_range_units`, `boomer_death_pop_hits` |
| Spitter  | `spitter_cone_hits`, `spitter_stand_time_s` |
| Jockey   | `jockey_ride_distance_units`, `jockey_ledge_throws` |
| Charger  | `charger_charge_total_units`, `charger_max_charge_units`, `charger_ledge_throws`, `charger_self_throws` |
| Tank     | `tank_max_survival_s`, `tank_total_survival_s`, `tank_passed_on_count`, `tank_handed_off_count`, `tank_distance_units` |
| Witch    | `witch_crown_attempts`, `witch_startles_caused`, `witch_chase_survived` |

Per-spawn detail rows live in `si_spawn_records` (one row per discrete SI
spawn). Toggleable via the `bizzymod_stats_log_si_spawns` CVar (default off).

### Health & inventory (mig 010)

| Stat                  | Source | DB |
|-----------------------|--------|----|
| Avg HP at saferoom    | `entered_checkpoint` event + `GetClientHealth()` | `hp_at_saferoom_sum/count` |
| Avg HP at heal events | `pills_used` / `heal_success` + HP snapshot | `hp_at_pills_*`, `hp_at_adrenaline_*`, `hp_at_medkit_*` |
| BW state entries/time | HP<40 polled by movement sampler | `bw_entries`, `bw_time_s` |
| Items hoarded into safe room | `GetPlayerWeaponSlot` scan at saferoom entry | `pills_hoarded`, `adrenaline_hoarded`, `medkits_hoarded`, `throwables_hoarded`, `defibs_hoarded` |
| Lowest HP survival    | tracked while alive | `career_bests.lowest_hp_survival` |
| Defib target points   | (extension point — schema ready) | `defib_target_points_sum` |
| Weapon-tier time      | (extension point — schema ready) | `weapon_t1/t2/melee/sniper_time_s` |

### Movement & positioning (mig 011 / movement.sp)

A `Timer` at 0.25s drives all of these. Position sampled via
`GetClientAbsOrigin`, deltas summed (with a 2000-unit teleport guard).

| Stat                  | DB |
|-----------------------|----|
| Distance traveled     | `distance_units` (extends 007) |
| Time alone            | `time_alone_s` (>750-unit threshold) |
| Breaks from group     | `breaks_from_group` (alone-state transitions) |
| Max team spread       | `max_team_spread_units` |
| Avg team spread       | `avg_team_spread_units` (sum/count flushed at session end) |
| Fall damage taken     | `fall_damage_taken` |
| Saferoom arrival order | `saferoom_arrivals` table (per-map) |

Time-leading / time-trailing intentionally not implemented in v1 —
requires map-aware "direction of progress" which is non-trivial without
Left4DHooks. Columns exist for a later iteration.

### Coordination & teamwork (mig 012 / coordination.sp)

| Stat                  | Source | DB |
|-----------------------|--------|----|
| Revive chains         | `revive_success` event + 60s lookback | `revive_events` table; `reviveChainsStarted/PartOf` counters |
| Save-of-save          | secondary lookback (saved → then saved someone within 60s) | `save_of_saves` counter |
| Tank focus participation | tank death + per-attacker damage log | `tank_kill_participations` |
| Boss damage attribution | per-victim damage log | `boss_damage_log` table |

### Round-shaping (mig 013 / tank_witch.sp + coordination.sp)

| Stat                  | Source | DB |
|-----------------------|--------|----|
| Tank summary cards    | tank_spawn → tank death | `tank_records` (one row per spawn) |
| Witch outcomes        | witch_spawn / startle / death | `witch_records` (one row per witch) |
| Crescendo events      | `panic_event_start` / `panic_event_finished` | `crescendo_events` |
| Finale waves          | (wired via `finale_radio_start` reset; per-wave hooks TBD) | `finale_waves` table |
| First-blood per round | (schema ready; capture in events.sp pending) | `first_bloods` counter |
| Saferoom door close   | `door_close.checkpoint=true` event | `saferoom_door_closes` + award `saferoom_save` |
| Untouchable map flag  | per-`player_hurt` filter, voids on any damage taken | resets at map start; used for awards |

### Versus / scavenge deep-dive (mig 014)

| Stat                  | Source | DB |
|-----------------------|--------|----|
| Survivor character    | (schema ready) | `survivors` catalog, `player_character_stats` |
| Scavenge per-gascan   | (schema ready; capture in events.sp pending) | `scavenge_gascans` table |
| Director placements   | tank_spawn + position at insert time | `director_placements` (extension point) |
| SI death cause breakdown | `player_death.weapon` classifier | `player_round_stats.died_by_*` |
| Survivor side preference | derived from `match_team_players` | `v_side_preference` view |
| Match comeback        | derived from running score deltas | `v_match_comebacks` view |
| Half-match score curve | window function over `match_maps` | `v_match_score_curve` view |
| Mercy time / health bonus | (schema ready) | `match_rounds.mercy_time_bonus`, `health_bonus` |

## Extension points

Sections marked _events.sp extension point_ have the DB column or award
code in place but the engine hook is not yet wired. Adding the hook is a
small, contained change — register the event in
`Bizzy_OnEventsInit()` and dispatch to `Bizzy_Score` / `Bizzy_Awards_Fire`
following the patterns already present in `events.sp`.

## Adding a new stat

1. **Pick where it lives.** Common rollup → `player_stats`. SI-specific
   → `player_si_stats`. Per-weapon → `player_weapon_stats`. Discrete
   achievement → new row in `awards` + `player_awards`.
2. **New migration:** `006_my_new_stat.sql` with an additive `ALTER
   TABLE ... ADD COLUMN` or `INSERT INTO awards`.
3. **Plugin:** hook the source event in `events.sp` and call
   `Bizzy_Score(...)` and/or `Bizzy_Awards_Fire(...)`.
4. **Flush:** if it's a rollup column, add it to the `INSERT ... ON
   DUPLICATE KEY UPDATE` in `Bizzy_Session_Flush()` (`session.sp`).
5. **Surface:** add it to a view in `005_views.sql` or directly query.

That's the entire loop. No `ALTER TABLE` cascade across half a dozen
columns; no parallel edit of a `DB_PLAYERS_TOTALPOINTS` string fragment.
