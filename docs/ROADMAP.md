# bizzymod-stats — recommendations & roadmap

> **Status note (2026-05-25):** Sections §1–§7 below are now fully
> implemented as of migrations 008–014 + the plugin's new `combat.sp`,
> `tank_witch.sp`, `movement.sp`, and `coordination.sp` modules. See
> [`STATS.md`](STATS.md) for the implementation map. The remaining
> sections (§8 campaign-specific, §9 character stats, §10 awards
> expansion, §11+ career/web/integrations) are still on the wishlist.

What we *could* add, organized by category and tiered by effort vs.
value. Each item lists:

- **What** — the stat/feature itself
- **Why** — concrete leaderboard or insight it unlocks
- **How** — engine source (event / netprop / inference)
- **Effort** — S (small, hours), M (medium, a day), L (large, multi-day)
- **Schema** — what tables change

The goal of this doc isn't to ship everything — it's to make trade-offs
visible so when you pick the next 10 items, you pick the highest-impact
ones first.

---

## Table of contents

1. [Combat granularity](#1-combat-granularity)
2. [Special-infected micro-stats](#2-special-infected-micro-stats)
3. [Health & inventory management](#3-health--inventory-management)
4. [Movement, positioning, traversal](#4-movement-positioning-traversal)
5. [Coordination & teamwork](#5-coordination--teamwork)
6. [Round-shaping events](#6-round-shaping-events)
7. [Versus / scavenge deep-dive additions](#7-versus--scavenge-deep-dive-additions)
8. [Campaign-mode-specific additions](#8-campaign-mode-specific-additions)
9. [Per-character (survivor identity) stats](#9-per-character-survivor-identity-stats)
10. [Awards expansion (75+ new ideas)](#10-awards-expansion)
11. [Career & progression layer](#11-career--progression-layer)
12. [Web / UX features](#12-web--ux-features)
13. [Operator tools](#13-operator-tools)
14. [Integrations](#14-integrations)
15. [Data integrity & anti-cheat](#15-data-integrity--anti-cheat)
16. [Performance & scale](#16-performance--scale)
17. [Suggested next 90-day plan](#17-suggested-next-90-day-plan)

---

## 1. Combat granularity

We track shots fired/hit/headshots, damage dealt/taken/friendly, kills
by victim type. We don't yet break down *how* damage was dealt. The
data is cheap to capture and adds enormous leaderboard variety.

| What | Why | How | Effort | Schema |
|------|-----|-----|--------|--------|
| **Damage by hitbox** (head/torso/limb) | Surfaces sniper vs spray-and-pray play; powers "true accuracy" metric | `player_hurt`'s `hitgroup` field (0=generic,1=head,2-3=chest,4-7=arms/legs) | S | extend `player_stats` w/ `dmg_hitgroup_*` |
| **Multi-kills per shot** | Shotgun mains finally get to brag; pipe-bomb headlines | Count consecutive `infected_death` events with same `attacker` + `weapon` within <50ms tick window | M | new `player_multikills` table (player_id, kills_in_burst, weapon_id, count) |
| **Kill assists** | The player who softened the special; tank-kill participation %  | Maintain per-SI damage log; on `player_death` of SI, credit anyone in last 5s | M | new `player_assists` table or column |
| **Time-to-kill per SI** | "Average seconds to kill a hunter" leaderboard | spawn epoch (`player_spawn` w/ team=infected) → `player_death` | S | extend `player_si_stats` w/ `ttk_min_ms`, `ttk_avg_ms`, `ttk_total_kills_s` |
| **DPS peak** | Burst-fire vs sustained players | Sliding 5-second damage windows; track peak | M | `career_bests.peak_dps` |
| **Long-distance kills** | Hunting Rifle / sniper bragging | `GetClientAbsOrigin` of attacker and victim at `player_death`; compute Euclidean distance | M | extend `player_stats.longest_kill_units`, `player_weapon_stats.longest_kill_units` |
| **Through-wall / penetration kills** | Sniper rifle penetrates; you killed something the engine had occluded | Use `TR_TraceRay` between attacker and victim at death; if a world surface intersects, it's a wall-bang | L | award + counter |
| **Damage taken in BW (black & white)** | Clutch metric: damage absorbed while at single-digit HP | `m_iHealth` < `m_iHealthBuffer` threshold check on `player_hurt` victim | M | extend `player_stats.bw_damage_taken` |
| **Damage from environment** | Fall, fire-from-own-molotov, getting boomed by ally | `player_hurt` w/ no attacker or attacker == victim | S | extend `player_stats.damage_environment` |
| **Friendly fire by weapon** | Chainsaw friendly damage is different from incidental SMG | already-captured `damage_friendly` + weapon_id join needs FF flag on `player_weapon_stats` | S | extend `player_weapon_stats.damage_friendly` |
| **FF impact: caused a teammate death?** | The difference between annoying and devastating FF | Look at `damage_friendly` events where victim died within 10s without other dmg | M | counter on `player_stats.ff_kills_caused` |
| **Reload count / mag-dump efficiency** | Skill heuristic — high-skill players reload more often | `weapon_reload` event; ratio of `shots_fired` / `reloads` | S | extend `player_weapon_stats.reloads` |
| **Time spent reloading** | Detect "reload-camping" or low-time-to-target shooters | weapon_reload start/end + animation duration table | M | `player_weapon_stats.reload_time_ms` |
| **Crit / crouch shots** | Some weapons reward crouch; surface that | `m_fFlags & FL_DUCKING` check at `weapon_fire` | S | extend `player_stats.crouch_shots` |
| **Inferno burn kills attributed** | We attribute molotov_burn_damage but not kills cleanly | already partially done; refine attribution window | S | nothing new |

**Recommendation:** ship hitgroup breakdown, multi-kills, kill assists,
TTK per SI, and damage-from-env first. These are all S/M effort and
unlock the biggest leaderboard variety per hour of work.

---

## 2. Special-infected micro-stats

Our `player_si_stats` table has the headline columns. There's a layer
of detail underneath each SI that defines high-skill versus baseline
play. These are what versus pros argue about.

### Smoker
- **Drag distance** — how far you yanked a survivor before being killed (`GetClientAbsOrigin` deltas during the active drag)
- **Smoker self-clear by survivor** (`tongue_release` event with survivor as `userid` — versus skill metric)
- **Choke duration** (already as `smoker_choke_damage`; add `smoker_choke_time_s`)
- **Smoker damage-per-pull** (peak per single grab vs average)
- **Tongue accuracy** — `ability_use` for smoker tongue, vs `tongue_grab` success (hit rate)

### Hunter
- **Pounce flight distance** (`m_vecOrigin` at `lunge_pounce` event start → at `pounce_stopped`)
- **Pounce duration** (`pounce_stopped` - `lunge_pounce` event timestamps)
- **Lunge angle** (vertical pounce gets the "Death From Above" gravy)
- **Skeeted pounces** (you got shot mid-pounce) — `ability_use` for lunge → no `lunge_pounce` event → death
- **Pounce damage histogram** — distribution of damage per pounce, not just total

### Boomer
- **Vomit range** — distance to nearest survivor at `boomer_vomit`
- **Death-pop hits** — survivors caught in `boomer_exploded` bile (already hooked, count it)
- **Perfect vomit by hit count** (we have the binary award; surface the number of hits per vomit)
- **Self-vomit** (your own vomit hit you somehow)

### Spitter
- **Spit cone hits** — number of survivors in spit before they escaped
- **Spit total stand-time** — how long survivors stood in the goo
- **Wasted spits** — `ability_use` for spit with no `player_hurt` from spitter weapon

### Jockey
- **Ride direction outcome** — did you ride them off a ledge? `m_iHealth` of victim → 0 during ride
- **Ride damage rate** (damage per second of ride)
- **Ride distance** (XY delta during ride)
- **Jockey ledge-throws** — incap or death within 2s of ride end

### Charger
- **Charge straight-line distance** — `charger_charge_start` to `charger_carry_end`
- **Ledge-charge kills** — survivor died during/just after charge with no other attacker
- **Scattering Ram quality** — # impacts × # hit (we count threshold; report the number)
- **Charger self-throw** (charged off ledge and died)

### Tank
- **Tank survival time** — spawn → death
- **Tank distance traveled** — sum of position deltas while alive
- **Tank survivors incapped** — counter of incaps during your tank life
- **Tank ledge throws** — `m_iHealth` of incapped survivor → 0 via fall
- **Tank pass-on** — handed off to another infected via timeout / skill
- **Rock arc time** — `tank_throw` → impact time delta (gauges how far you led)
- **Rock leading** — distance survivor moved between throw and impact

### Witch
- **Crown angle** — was it straight in face (canonical) or off-angle?
- **Witch startle source** — who startled the witch?
- **Witch chase distance** — did she chase you 50 feet or hit you immediately?

**Effort:** mostly S each (existing event handlers extended); collectively
a one-week sprint. **Schema:** several `ALTER TABLE player_si_stats ADD
COLUMN` migrations; consider also a new `si_events` granular table for
the histogram-style data.

---

## 3. Health & inventory management

Currently invisible to the schema but huge for skill differentiation.

| What | Why | How | Effort |
|------|-----|-----|--------|
| **Average HP at saferoom arrival** | "Tank" survivors take damage so others don't | `map_transition` + `m_iHealth` snapshot | S |
| **Times entered BW state** | Clutch survivors live in BW | `player_hurt` victim where new HP < 40 | S |
| **HP when used pills/adrenaline** | Hoarders vs reactive players | `pills_used` + victim HP at event | S |
| **Items hoarded into saferoom** | Used to penalize; could surface as positive ("stockpile") | At `map_transition`, snapshot each survivor's inventory slots | M |
| **Defib priority** | Did you defib the highest-scoring teammate? | `defibrillator_used` + cross-reference target's session score | M |
| **Pills/adrenaline given vs hoarded** | Already partly tracked; surface ratio | existing data | S |
| **Medkit time-of-use** | Heal-early vs heal-late style | already tracked time-of-event | S |
| **Self-heal vs heal-other ratio** | Selfish vs supportive | derived from `medkits_used` vs `medkits_used_on_other` | S |
| **T1 vs T2 weapon time** | "Always upgrades" / "rifle-only" patterns | weapon-slot tracking via `player_use` events | M |
| **Most-favored weapon by playtime** | Different from kills — what they CARRY | extend `player_weapon_stats.time_held_s` (already in schema, not yet captured) | M |
| **Defib carry stats** | Carried into finale = good supportive player | snapshot at `finale_start` | S |

---

## 4. Movement, positioning, traversal

The most under-utilized data in L4D2. Engine exposes position every
tick. We could derive 20 stats from a single `OnGameFrame` sampler that
runs at 4 Hz instead of 60 Hz.

| What | Why | How | Effort |
|------|-----|-----|--------|
| **Distance traveled per map / session / career** | "Most active runner" leaderboard | `m_vecOrigin` deltas in throttled OnGameFrame (4 Hz) | M |
| **Time alone (>X units from teammates)** | "Lone wolf" vs "stays grouped" | OnGameFrame sampler computes nearest-teammate distance | M |
| **Time leading the group** | Pointman / rusher style | farthest forward survivor in direction of progress | M |
| **Time trailing the group** | "Always last" style | inverse of above | S |
| **Number of breaks from group** | Discipline metric | transitions in/out of "alone" state | M |
| **Times left teammate behind to die** | Negative-style metric (gentle) | teammate incapped + you >X units away + no return within 30s | M |
| **Falls / fall damage taken** | The "Ellis Special" award territory | `player_hurt` w/ weapon=="world" + attacker==victim | S |
| **Self-cliff (jumped off to die)** | Niche but funny | `player_death` w/ weapon=="world" + no attacker | S |
| **Bot bounces** | Took over a bot OR got booted out by re-join | `OnClientPostAdminCheck` correlates with bot-team-switch | M |
| **Saferoom arrival ordering** | "Always first in / last in" | order players cross saferoom trigger | M |
| **Average pace** | Distance / playtime as ratio | derived | S |
| **Stairs / ladder usage** | Pure curiosity; could feed map-design analytics | nav-mesh queries (Left4DHooks) | L |

**Recommendation:** the OnGameFrame sampler at 4 Hz is the unlock —
build it once, every movement stat above falls out cheaply. Watch the
perf budget; sampling above 8 Hz starts to matter on busy servers.

---

## 5. Coordination & teamwork

This is the headline insight you can't get any other way: **how well
this group of players plays together**.

| What | Why | How | Effort |
|------|-----|-----|--------|
| **Revive chains** | A → revived B → revived C → revived A in 60s | track `revive_success` graph per round | M |
| **Save-of-save** | You saved someone who then saved someone | second-order events from `protect` / `revive` | M |
| **Spread heatmap** | Average team spread over the round | OnGameFrame max-pairwise distance | M |
| **Time stacked vs spread** | Tight-formation playstyle | same sampler, with histograms | M |
| **SI focus** | Did you focus the same SI as your teammates? | damage attribution to common targets | M |
| **Protect-revive ratio** | "Proactive savior" vs "reactive medic" | already have both counts; derive ratio | S |
| **Tank focus participation** | % of total tank damage you contributed | tank death event + per-attacker damage log | M |
| **Witch dispatch contribution** | Same for witches | analogous | M |
| **Throwable assists** | Your pipe distracted commons that would have hit a teammate | tricky — proximity-based heuristic | L |
| **Trade rate** (versus) | Your team's incapped survivor = your trade | versus only; track round-end state | M |

**Recommendation:** revive chains and tank focus participation are
high-value, MVP-of-round style metrics. Worth building.

---

## 6. Round-shaping events

L4D2 has discrete moments where the game pivots. We track the moment;
we don't track the *outcome of* the moment.

| What | Why | How | Effort |
|------|-----|-----|--------|
| **Tank summary card** | Per-tank-spawn: survival_s, distance, incaps, kills, was-passed-on | Hook `tank_spawn` + `player_death` (where victim_class==Tank) | M |
| **Tank kill participation %** | Top survivor damage contributor per tank | per-tank damage log | M |
| **Witch outcome** | crowned / killed / avoided / killed-after-startle | hook `witch_killed` and check `oneshot` + sequence | S |
| **Saferoom save** | Did the door-closer (rescuer) save the team? | `door_closed` event + late-arriver check | M |
| **Finale wave survival** | How many waves did you survive? | finale_wave_* events | M |
| **Crescendo event survival** | First-try vs multiple deaths during a panic event | `panic_event_start/finished` + deaths during | M |
| **First-blood (versus)** | First kill of the round | `player_death` first occurrence within match_round | S |
| **First-bloomed (versus)** | First survivor down | first `player_incapacitated` per round | S |
| **Last-stand seconds** | Time alive as last survivor on the team | derive from team alive count + your alive state | M |

---

## 7. Versus / scavenge deep-dive additions

We have the match/round/team scaffolding. Plenty more to slot into it.

| What | Why | How | Effort |
|------|-----|-----|--------|
| **SI spawn time after death** | "How fast do you re-engage" | `player_spawn` (team=infected) timestamp minus your previous `player_death` | S |
| **Ghost time before materialization** | "Camping ghost" detection | Left4DHooks `L4D_OnEnterGhostState` / `L4D_OnMaterializeFromGhost` | M (requires extension) |
| **Ghost position deltas** | Did you ghost-walk to a setup spot? | OnGameFrame while in ghost state | M |
| **SI death cause breakdown** | Melee / gun / fire / fall / self | already in `player_death.weapon`; just surface | S |
| **Survivor side preference / record** | Are you a better A or B player? | per-letter w/l within career | S |
| **Match comeback** | Won despite trailing by ≥500 at map N | post-game derivation from match_maps trends | S |
| **Map carry** | One map's delta determined match | post-game derivation | S |
| **Tank-round outcome** | Win/loss split by "was there a tank this round" | already have `tank_appeared`; just join | S |
| **Witch-round outcome** | Same for witch | already have `witch_appeared` | S |
| **Half-match score curve** | Plot running score as ASCII / SVG sparkline | match_rounds time-series | M |
| **Scavenge per-gascan** | Each gascan pour as its own row | new `scavenge_gascans` table with map_round_id, pourer_id, gascan_seq, interrupted | M |
| **Scavenge defense success rate** | % of gascans defended | derive from above | S |
| **Mercy round / time bonus** | Versus has a clock; how much was on it? | `versus_round_start` / `round_end` timestamps | S |
| **Director's tank/witch placement** | Where did Director put them on this map? | `tank_spawn` + position | M |
| **Survivor team character distribution** | Which 4 survivors did you play? | `player_spawn` w/ model name | S |

---

## 8. Campaign-mode-specific additions

Co-op / Realism / Mutations get less love in versus-focused stat
systems. There's plenty of structure we can surface.

| What | Why | How | Effort |
|------|-----|-----|--------|
| **Campaign run records** | Best time per (campaign, difficulty, team_size) | aggregate per finale_win | M |
| **Map-by-map best time** | Already have `timed_maps`; need leaderboard view | view | S |
| **Difficulty progression** | "First Expert finish" achievement | first finale_win on Expert per player | S |
| **Realism survival** | Track Realism wins separately | derive from `gamemode_id` | S |
| **Death-less campaigns** | Whole campaign without a single death | aggregate `match_rounds.deaths==0` | S |
| **Solo campaign** | Finished a campaign as the only human | derive at finale_win | M |
| **Friendly-fire-free campaign** | "No FF" badge | derive | S |
| **No-medkit campaign** | Iron-man flavor | derive | M |
| **All-headshot campaign** | Every kill was a headshot | check `headshots == kills` for the run | M |
| **Map-restart count** | How many times your team wiped before clearing | `round_end` w/ reason "mission_lost" counted | S |
| **Crescendo no-deaths** | Cleared a panic event without anyone going down | crescendo events + deaths during | S |
| **Speedrun mode** | Best time on each campaign, ignoring deaths | `timed_maps` filtered | S |
| **Survival best times per map** | Already supported by `timed_maps` for survival mode | view | S |

---

## 9. Per-character (survivor identity) stats

L4D characters are visually distinct. Tracking which one you play
unlocks character mains' leaderboards. Captured via the survivor's
model entity name.

| What | Why | How | Effort |
|------|-----|-----|--------|
| **Per-character session counts** | "Nick main" / "Ellis main" | `m_survivorCharacter` netprop or `m_szModelName` substring | S |
| **Per-character win rate** | Which character is most-winning for you? | join with sessions/match_team_players | S |
| **Favorite character** | Single derived stat: most-played | view | S |
| **Character + mode matrix** | "Coach in Realism" stat | rollup | S |

New table: `player_character_stats(player_id, character_id,
sessions, wins, losses, points, playtime_s)`.
Catalog: `survivors(id, code, name, game_id)` —
Bill/Francis/Louis/Zoey for L4D1, Nick/Coach/Ellis/Rochelle for L4D2.

---

## 10. Awards expansion

Awards are data — adding 50+ is a single INSERT migration plus a hook
or counter. Suggested additions, grouped by category:

### Skill awards (precision / efficiency)
- **Sharpshooter** — sustained accuracy ≥75% over 10+ sessions
- **Headshot Master** — sustained HS% ≥40% over 10+ sessions
- **No-Scoper** — kill with hunting rifle / sniper without scoping
- **Quickdraw** — finished tank in <30s
- **Untouchable** — finished a finale without taking damage
- **Sniper** — kill at >1500 units distance
- **Boomstick** — 3+ commons killed with one shotgun shell
- **Pyromaniac** — kill 5+ with one molotov
- **Bomberman** — kill 8+ with one pipe bomb
- **Reload Master** — high reloads-per-engagement (paranoid reloader)

### Clutch awards
- **Last Stand** — won round as last survivor alive
- **MVP of Round** — top points in a single round
- **Comeback Kid** — won match after trailing by ≥1000 at map 2
- **One-shot Tank** — solo killed a tank with no other survivor damage
- **Cliffside Save** — saved a teammate from a ledge in last 1s
- **Defib Pro** — used 10 defibs total
- **Bodyguard Elite** — 50+ protect awards
- **Last Door** — closed the saferoom door alone

### Discipline / playstyle
- **Pacifist** — finished a finale with <20 kills
- **Brawler** — 50%+ kills were melee
- **Loadout Purist** — never picked up a special item
- **Gunslinger** — primary-pistol kills > primary-rifle kills
- **Iron Stomach** — never used pills in a session
- **Lightweight** — never used medkits in a session
- **Generous** — gave more pills than you took
- **Doctor** — most heal-other in a session
- **Wingman** — defib 4 teammates in one match
- **Buddy** — finished a campaign with same teammate 10+ times

### Negative / humorous
- **Friendly Fire Champion** — most FF in a session (rotates daily)
- **Witch Bait** — most witches startled
- **Self-Destruct** — most self-deaths
- **Boomer Magnet** — most times vomited on
- **Pin Cushion** — most times pinned by SI
- **Lemming** — most fall-deaths
- **Tax Collector** — most pills/medkits hoarded into saferoom

### Versus-specific
- **Specialist** — most-pounce-damage in a match
- **Tank Whisperer** — won 3+ tank rounds as infected
- **Witch Crowner** — crowned a witch in a versus match
- **Smoker Sniper** — drag distance >2000 units in one pull
- **Charger King** — 4+ impact Scattering Ram
- **Boomer Perfect** — 4-hit perfect vomit
- **Ghost Walker** — longest ghost time before materializing (mind-game)
- **First Blood** — first kill of the round 10+ times
- **Map Carry** — your map score was the deciding margin

### Streak awards
- **Kill Streak ×10/×25/×50/×100** — kills without dying
- **Win Streak ×3/×5/×10** — consecutive match wins
- **Headshot Streak ×10** — 10 consecutive kills, all headshots
- **No-Death Streak** — N rounds without dying

### Career milestones
- **100 / 1k / 10k / 100k kills**
- **10 / 100 / 1000 hours played**
- **First Expert finish**
- **First Realism Expert finish**
- **All 5 official L4D2 campaigns finished**
- **All L4D1 campaigns finished**
- **All mutations played at least once**

That's ~70 new awards across the categories. Adding them is one
migration + counter logic — a one-day task to ship the whole pack.

---

## 11. Career & progression layer

Right now stats are flat counters. A progression layer turns them into
something players chase.

### Level / prestige
- XP from points; level curve (e.g. `level = sqrt(points/100)`)
- Prestige resets at level cap, with a permanent badge
- Season-bound levels (resets every 3 months) vs lifetime
- Per-mode levels (versus level vs co-op level)

### Daily / weekly challenges
- "Kill 100 commons today" / "Win a match this week"
- Stored in `player_challenges(player_id, challenge_id, period_start, progress, completed_at)`
- Generated from a templates catalog
- Award bonus points or unlock badges

### Seasons
- Define seasons in a `seasons(id, name, started_at, ended_at)` table
- Per-season `player_season_stats` (parallel to player_stats but filtered)
- All-time vs current-season views
- Season recap page ("you ranked #42 globally in Season 3")

### Badges
- Distinct from awards — badges are *displayed*, awards are *counted*
- `player_badges(player_id, badge_id, earned_at, display_priority)`
- Custom badge images, optional steam-style "shiny" variant
- Equippable (show top 3 on your profile)

### Title system
- Top-N rank on a leaderboard = title ("Top 100 Pouncer", "Tank Killer #1")
- Refreshed nightly
- Displayed next to name in chat (CVAR-toggleable)

---

## 12. Web / UX features

The current web stub is intentionally minimal. The high-value additions:

| Feature | Effort | Notes |
|---------|--------|-------|
| **Steam OpenID login** | M | Standard `openid.steamcommunity.com` flow; PHP libraries exist |
| **Player profile chart pack** | M | sparklines for points-over-time, recent matches, per-mode bars |
| **Player comparison** | M | side-by-side two players |
| **Match replay timeline** | L | reads `award_events` and renders a chronological feed |
| **Live match overlay (OBS source)** | M | a tight HTML page polling current match every 2s |
| **Search** | S | players by name/steamid; maps; servers |
| **Filters** | M | date range, gamemode, server, map across all leaderboards |
| **Heatmaps** | L | death/kill locations per map (requires position capture) |
| **Discord bot** | M | webhook on match end; `!rank @user` queries |
| **Public REST API** | M | `/api/v1/players/{id}`, `/api/v1/matches/{id}`, etc. |
| **GraphQL endpoint** | L | one schema; consumed by future SPA frontend |
| **Server browser** | S | list of registered servers w/ recent activity |
| **Charts via Chart.js** | S | minimal-dep chart rendering |
| **Mobile-responsive layout** | S | tweak the layout.phtml CSS |
| **Per-player RSS feed** | S | "your recent matches" via RSS |
| **OG / Twitter card previews** | S | nice link sharing |
| **Internationalization** | M | already partly set up via `lang/` files in legacy; modernize |

---

## 13. Operator tools

What server admins ask for after first month of running stats:

| Feature | Effort | Notes |
|---------|--------|-------|
| **Web admin panel** | L | login w/ admin steamid allowlist; edit/recompute/wipe |
| **Stat-edit audit log** | S | `stat_audit(at, who, action, before, after)` |
| **Manual player merge** | M | someone played on two steamids; merge into one |
| **Smurf detection** | M | very high PPM ratio on a new account; flag for review |
| **Vote-kick reporting** | S | track who was kicked, by whom, for what — separate from cheat detection |
| **AFK no-credit** | S | don't grant playtime to clients with no movement/input in last 60s |
| **Premium-server tagging** | S | `servers.is_official` flag; restrict leaderboards |
| **League / tournament mode** | L | finite-roster matches; bracket UI |
| **Match replay export** | M | dump match_rounds + player_round_stats as JSON |
| **Discord notification hooks per server** | S | webhook URL per `servers` row |
| **Stat freeze (suspect cheater)** | S | flag → no new stats recorded for that player |
| **Auto-ban integration** (with SourceBans++) | M | block_until column on players |
| **Server uptime tracking** | S | `servers.last_seen` is there; visualize |

---

## 14. Integrations

| Integration | Effort | Notes |
|-------------|--------|-------|
| **Discord webhooks** — match-end summaries, MOTD changes, big award unlocks | S | `kv_settings` discord_webhook_url, fired from web cron |
| **Discord bot** — slash commands `/rank`, `/match latest`, `/top10` | M | one-off bot using same DB read-only |
| **Twitch chatbot** — `!stats` returns player profile link | S | similar |
| **OBS browser source** — live stats overlay for streamers | M | a polling HTML page |
| **Steam widget** — embeddable per-player card | S | tiny HTML/SVG with cache headers |
| **Public JSON REST API** | M | versioned, rate-limited |
| **Public GraphQL API** | L | rich querying for fan-projects |
| **Webhooks out** — let others subscribe to match-end events | M | `webhooks(url, events_mask, secret)` table |
| **Server-sent events** for live updates | M | SSE endpoint; the live overlay subscribes |
| **Cabinet of WebSocket** — real-time push for live ladders | L | full async server |
| **Sourcebans++ link** — show ban status on player profile | S | optional schema join |
| **OpenSearch / Elasticsearch sync** | L | for huge servers wanting full-text on chat |
| **Grafana dashboard preset** | M | export ready-to-import dashboards using MySQL datasource |
| **Prometheus metrics endpoint** | M | per-server stats as `bizzy_*_total` counters |

---

## 15. Data integrity & anti-cheat

| Check | Effort | Notes |
|-------|--------|-------|
| **Sanity bounds** — reject rows w/ negative time, impossibly high HS rate | S | trigger or pre-insert validation in plugin |
| **PPM ceiling** — flag sessions with PPM > engine-max | S | post-hoc cron query |
| **Headshot ratio anomaly** — flag accounts w/ sustained ratio > human-plausible | M | rolling-window analysis |
| **Geographic anomaly** — same steamid from multiple countries in <hour | M | IP+country logging already exists |
| **Multi-server identity merge** — same account from 2 servers same minute | M | sessions overlap check |
| **Account verification** (Steam OpenID linked to in-game stats) | M | confirms you control the steamid |
| **Replay-of-replay protection** — duplicate match insert idempotency | S | unique key on (server_id, started_at, campaign) |
| **Plugin signature pin** — store the plugin version per session | S | new column |
| **Stat checksum chain** | M | hash of session stats → enables tamper detection if DB is leaked/dumped/modified |

---

## 16. Performance & scale

Once you have 100k+ players and 10M+ sessions:

| Optimization | Effort | When to do it |
|--------------|--------|---------------|
| **Read replicas** for the web tier | M | when web load impacts plugin writes |
| **Materialized rollup tables** (refreshed hourly by cron) | M | when leaderboard queries take >1s |
| **Old-session archival** — move sessions >1 year to `sessions_archive` | M | when sessions table is >100GB |
| **Index review pass** | S | quarterly |
| **Connection pooling on plugin side** | N/A | SM Database handle already pools |
| **Partitioning sessions by year** | M | at very large scale |
| **Awards events firehose** — separate write path (Kafka / Redis stream) | L | only at huge scale |
| **CDN for static web assets** | S | always |
| **Read-only DB user for web tier** | S | always (security) |
| **Slow query log monitoring** | S | always |

---

## 17. Suggested next 90-day plan

If you wanted to ship the most-impactful subset in the next quarter,
here's a sequenced plan. Each box is ~1-2 weeks.

```
┌─────────────────────────────────────────────────────────┐
│ WEEK 1-2: Combat granularity                            │
│ - Damage by hitgroup                                    │
│ - Kill assists (per-SI damage log + credit window)      │
│ - Time-to-kill per SI                                   │
│ - Multi-kills per shot                                  │
│ + Migration 008, plugin event extension                 │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ WEEK 3-4: SI micro-stats                                │
│ - Smoker drag distance + self-clear                     │
│ - Hunter pounce flight/duration                         │
│ - Tank summary cards                                    │
│ - Witch outcome breakdown                               │
│ + Migration 009                                         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ WEEK 5-6: Movement sampler                              │
│ - OnGameFrame @ 4 Hz sampler                            │
│ - Distance traveled, time-alone, leader/trailer time    │
│ - Spread heatmap data                                   │
│ + Migration 010, new movement.sp module                 │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ WEEK 7-8: Awards expansion + character stats            │
│ - 50+ new awards (Migration 011)                        │
│ - Per-character stats (Migration 012)                   │
│ - All trigger logic in events.sp                        │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ WEEK 9-10: Career & progression                         │
│ - XP / level / prestige system                          │
│ - Seasons table + season-scoped views                   │
│ - Daily/weekly challenges scaffold                      │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ WEEK 11-12: Web overhaul                                │
│ - Steam OpenID login                                    │
│ - Player profile chart pack                             │
│ - Live match overlay (OBS source)                       │
│ - Public REST API v1                                    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ WEEK 13: Discord integration                            │
│ - Match-end webhooks                                    │
│ - Slash-command bot                                     │
└─────────────────────────────────────────────────────────┘
```

Total: ~50 new stat dimensions, ~70 new awards, character tracking,
movement intelligence, progression layer, modernized web tier, and
Discord integration.

If you want a shorter list, the **highest-impact-per-hour subset** is:

1. **Damage by hitgroup** (S, unlocks "true accuracy")
2. **Kill assists** (M, finally credits the support player)
3. **Tank summary cards** (M, biggest moment-of-the-round insight)
4. **OnGameFrame movement sampler** (M, unlocks 5+ metrics)
5. **70 new awards** (S, content density)
6. **Per-character stats** (S, "main" leaderboards)
7. **Steam OpenID + profile pages** (M, makes the web tier feel real)
8. **Discord match-end webhooks** (S, community engagement)

That's ~2-3 weeks of focused work and roughly triples the "wow" factor
of bizzymod-stats without changing the architecture.

---

## What we intentionally don't recommend

- **Per-tick position recording** (60 Hz sampling) — overkill, would
  multiply DB writes by 60× for marginal precision over 4 Hz sampling.
- **Voice chat analytics** — privacy minefield; not worth it.
- **Aimbot detection ML** — better tools exist; reproducing them here
  would distract from stats.
- **Cross-game stat porting** (TF2/CS) — different metric models, no
  shared schema makes sense.
- **Player ELO / matchmaking** — implies you'll run matchmaking, which
  is a whole product area.
- **Real-money rewards / item shop** — Valve-EULA territory; stay out.

---

## Open questions for prioritization

- How many servers will run bizzymod-stats? (1 = focus on depth; many = focus on multi-tenancy)
- Audience size? (small clan = skip leagues/tournaments; large league = build them)
- Web traffic shape? (hobby site = SQLite cache; production = read replicas)
- Modded engine compatibility? (confogl / Custom Anti-Cheat) — some features depend on engine-clean signal
- L4D1 priority? (most additions are L4D2-flavored; L4D1 parity needs separate work)

Talk through any of these and we can re-prioritize.
