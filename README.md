# bizzymod-stats

A modern player-statistics and ranking system for **Left 4 Dead 1** and
**Left 4 Dead 2** game servers. Captures everything from kills and
headshots to per-round versus match outcomes, win/loss streaks, MVP
breakdowns, throwable usage, and career bests — all into a normalized
MySQL database with both a SourceMod plugin (server-side) and a PHP
front-end (read-side).

```
   ┌──────────────────────┐        async writes        ┌────────────────────┐
   │  L4D / L4D2 server   │ ────────────────────────►  │     MySQL 8        │
   │  + SourceMod 1.12    │  batched in transactions   │  normalized schema │
   │  + bizzymod_stats.smx│  no game-tick blocking     │  + migrations      │
   └──────────────────────┘                            └──────────┬─────────┘
                                                                  │ reads
                                                                  ▼
                                                       ┌────────────────────┐
                                                       │  web (PHP 8 / PDO) │
                                                       │  leaderboards,     │
                                                       │  matches, profiles │
                                                       └────────────────────┘
```

This README is the full operator's manual: prerequisites, install,
upgrade, build-from-source, release, web setup, every ConVar,
troubleshooting, and how to extend.

---

## Table of contents

1. [What you get](#what-you-get)
2. [Prerequisites](#prerequisites)
3. [Quick start](#quick-start)
4. [Install — full walkthrough](#install--full-walkthrough)
   - [Database](#1-database)
   - [SourceMod plugin](#2-sourcemod-plugin)
   - [Web front-end (optional)](#3-web-front-end-optional)
5. [Upgrading](#upgrading)
6. [Building from source](#building-from-source)
7. [Releasing](#releasing)
8. [What is captured](#what-is-captured)
9. [ConVar reference](#convar-reference)
10. [Commands](#commands)
11. [Troubleshooting](#troubleshooting)
12. [Extending bizzymod-stats](#extending-bizzymod-stats)
13. [Repository layout](#repository-layout)
14. [Versus / round tracking deep dive](#versus--round-tracking-deep-dive)
15. [License & credits](#license--credits)

---

## What you get

- **A compiled SourceMod 1.12 plugin** (`bizzymod_stats.smx`) that hooks
  ~50 game events and writes asynchronously to MySQL — never blocks the
  game tick.
- **A normalized MySQL 8 schema** (14 numbered migrations, 62 tables/views, 82 awards) tracking:
  - **Per-player rollups** by gamemode + difficulty (points, playtime, accuracy, headshot %, damage classification)
  - **Per-weapon stats** with auto-extending catalog + hitgroup breakdown
  - **Per-special-infected stats** — pounces (with flight distance + skeet detection), drags, vomits, rides, charges, tank punches/rocks
  - **Awards** as data, not columns — adding new ones is one INSERT
  - **Versus / Realism Versus / Scavenge match tracking** — full match → map → round → per-player MVP hierarchy with persistent team identity across side-swaps
  - **Win/loss/streak rollups** with atomic SQL streak math
  - **Career bests** — most kills in a session, biggest tank punch, longest kill streak, peak DPS, longest sniper kill
  - **Combat granularity** — hitgroup breakdown, kill assists, multi-kills per shot (2/3/4/5+), TTK per SI, DPS rolling-window peak, BW-state damage, environment damage, FF kills caused
  - **Tank summary cards** — per-tank-spawn: survival time, distance traveled, incaps caused, kills caused, controller handoffs
  - **Witch encounter records** — outcome (crowned/killed/avoided/killed-after-startle), startler, chase distance
  - **Crescendo events + finale waves** — survival outcomes per panic event
  - **Revive chain detection** — A→B→C linkage within 60s windows
  - **Saferoom arrival ordering** — first-in / last-in leaderboards
  - **Director boss placements** — XYZ position of each tank/witch spawn for heatmaps
  - **Throwables** (pipe / molotov / bile thrown + kills + burn damage)
  - **Movement intelligence** — distance traveled, time-alone, team spread, weapon-tier time held (via 4Hz position sampler)
  - **Pin tracking** (smoker/hunter/jockey/charger, vomited on, self-escape count)
  - **Per-character stats** (Nick/Coach/Ellis/Rochelle + Bill/Francis/Louis/Zoey)
- **A Python migration runner** with sha256 drift detection.
- **Self-hosted GitHub Actions CI/CD** — see [`docs/CI.md`](docs/CI.md).
- **A bash-driven test harness** (`tests/run.sh`) that runs locally and in CI: compile → migrations → idempotency → seed sanity → FK probe → view sanity.
- **A minimal PHP front-end** demonstrating the schema is queryable.

---

## Prerequisites

| Component       | Requirement                                                            |
|-----------------|------------------------------------------------------------------------|
| Game server     | Left 4 Dead 1 or Left 4 Dead 2 with SourceMod **1.12+** installed       |
| Database        | MySQL **8.0+** (works on 5.7+ with utf8mb4)                            |
| Migration tool  | Python **3.10+** with `pymysql`                                        |
| Web (optional)  | PHP **8.1+** with `pdo_mysql`                                           |
| Build (optional)| [sourceknight](https://github.com/maxime1907/action-sourceknight) **or** raw `spcomp` from SM 1.12 |

SourceMod requires Metamod:Source. If your server doesn't have either,
install them first — see https://wiki.alliedmods.net/Installing_SourceMod.

---

## Quick start

```bash
# 1. Clone
git clone https://github.com/<you>/bizzymod-stats.git
cd bizzymod-stats

# 2. Database — applies all 7 migrations
pip install -r schema/scripts/requirements.txt
python schema/scripts/migrate.py \
    --host 127.0.0.1 --user root --password secret \
    --database bizzymod_stats

# 3. Plugin — grab a release zip from GitHub Releases, extract into
#    your game's left4dead2/ directory, edit databases.cfg
#    (see step 2 below)

# 4. Web (optional)
cd web && cp config.example.php config.php
# edit config.php with DB creds
php -S 127.0.0.1:8080 -t public
```

---

## Install — full walkthrough

### 1. Database

You need an empty MySQL 8 database and a user that can write to it.

```bash
sudo mysql -u root -p
```

```sql
CREATE DATABASE bizzymod_stats
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'bizzymod_stats'@'%' IDENTIFIED BY 'use-a-real-password';
GRANT ALL ON bizzymod_stats.* TO 'bizzymod_stats'@'%';
FLUSH PRIVILEGES;
```

Apply the migrations:

```bash
cd schema/scripts
pip install -r requirements.txt

python migrate.py \
    --host db.internal \
    --user bizzymod_stats \
    --password 'use-a-real-password' \
    --database bizzymod_stats
```

You should see all migrations apply (`001_init_schema` through
`007_extended_stats`) and on a second run "Database is up to date".

**Windows users** can use the bundled PowerShell script:

```powershell
.\schema\scripts\install.ps1 -Database bizzymod_stats -DbUser root
```

### 2. SourceMod plugin

Download the latest release zip from the [Releases](../../releases) page
and extract it into your game's `left4dead2/` (or `left4dead/` for L4D1)
directory:

```
left4dead2/
└── addons/
    └── sourcemod/
        ├── plugins/bizzymod_stats.smx
        ├── gamedata/bizzymod_stats.txt
        ├── translations/bizzymod_stats.phrases.txt
        └── configs/
            └── bizzymod_stats/
                ├── databases.cfg.example
                └── bizzymod_stats.cfg.example
```

**Add the DB entry to your `databases.cfg`.** Open
`left4dead2/addons/sourcemod/configs/databases.cfg` and add an entry
named exactly **`bizzymod_stats`** (this name is hard-coded in the plugin):

```c
"Databases"
{
    "default" { /* your existing entry */ }

    "bizzymod_stats"
    {
        "driver"   "mysql"
        "host"     "db.internal"
        "database" "bizzymod_stats"
        "user"     "bizzymod_stats"
        "pass"     "use-a-real-password"
        "port"     "3306"
        "timeout"  "30"
    }
}
```

**Optional: install the default CVar config:**

```bash
cp configs/bizzymod_stats/bizzymod_stats.cfg.example  cfg/sourcemod/bizzymod_stats.cfg
```

(The plugin auto-execs this file at startup if it exists.)

**Start the server** (or `sm plugins load bizzymod_stats`). Watch the log:

```
[bizzymod-stats] online as server_id=1 (key=4b2c…)
```

If you see `cannot connect to 'bizzymod_stats' database`, your databases.cfg
entry is wrong or the DB is unreachable. The plugin intentionally
fails-loudly via `SetFailState` rather than silently losing stats.

The plugin creates a stable per-server identity file at
`cfg/sourcemod/bizzymod_stats.server_key` (32 hex chars). **Don't delete this**
casually — it's how the server is identified in the `servers` table.
Deleting it creates a new server row on next start; old stats are not
lost but new stats land under a new `server_id`.

### 3. Web front-end (optional)

The web tier is a deliberately minimal PHP 8 / PDO stub that demonstrates
the schema is queryable. Production-grade UI is left for later.

```bash
cd web
cp config.example.php config.php
# edit config.php — set $cfg['db'] values
php -S 127.0.0.1:8080 -t public
```

Open http://127.0.0.1:8080. Pages available:

- `/`              — top players (uses `v_top_players` view)
- `/matches.php`   — recent versus matches
- `/match.php?id=` — single match detail with per-round breakdown
- `/player.php?id=` — player profile + per-mode + awards
- `/awards.php`    — award leaderboards
- `/server.php`    — server list + recent sessions

For production, point an nginx/Apache document root at `web/public/`. You
must also ensure `web/config.php` is not web-accessible (it's outside
`public/` by design).

---

## Upgrading

bizzymod-stats uses **forward-only additive migrations**. To upgrade:

```bash
git pull
python schema/scripts/migrate.py --host ... --user ... --database bizzymod_stats
# Then redeploy the new .smx from the release zip and restart the server.
```

The migration runner records the sha256 of every applied file. If you
edit a migration that's already been applied, the runner emits a
**warning** but does not roll back — additive changes only ever require
new migration files.

Major-version bumps (`v3.0.0` ← `v2.x.x`) may include schema changes
that drop columns or require manual data migration; check the release
notes.

---

## Building from source

### Option A: sourceknight (recommended, what CI uses)

[sourceknight](https://github.com/maxime1907/action-sourceknight) is a
SourcePawn build orchestrator. Install it, then:

```bash
sourceknight build
ls .sourceknight/**/bizzymod_stats.smx
```

The `sourceknight.yaml` at the repo root pins SourceMod 1.12 and
optionally pulls Left4DHooks and multicolors for future use.

### Option B: raw spcomp

Download SourceMod 1.12 from https://www.sourcemod.net/downloads.php
(Windows or Linux build). The toolchain ships `spcomp` and the standard
include set in `addons/sourcemod/scripting/`.

```bash
# Linux / WSL / git-bash
spcomp \
  -i/path/to/sourcemod/addons/sourcemod/scripting/include \
  -iplugin/scripting \
  plugin/scripting/bizzymod_stats.sp \
  -oplugin/build/bizzymod_stats.smx
```

The compile should produce zero errors and a small number of harmless
unused-symbol warnings.

### What the plugin needs at compile time

Only the stock SourceMod 1.12 include set (`sourcemod.inc`,
`sdktools.inc`, `sdkhooks.inc`, `clientprefs.inc`, `adminmenu.inc`). No
third-party extension required. (Left4DHooks is listed in
`sourceknight.yaml` as optional for future use.)

---

## Releasing

CI runs on a **self-hosted GitHub Actions runner** so we control the
SourceMod toolchain and Docker. Setup instructions for the runner live
in [`docs/CI.md`](docs/CI.md) — the short version is:

```bash
# Install prereqs on the runner box
sudo bash .github/runner-setup.sh

# Register the runner with GitHub
# (one-time-token from repo Settings → Actions → Runners → New)
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -O -L https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64.tar.gz
tar xzf actions-runner-linux-x64.tar.gz
./config.sh --url https://github.com/<you>/bizzymod-stats --token <TOKEN>
sudo ./svc.sh install && sudo ./svc.sh start
```

To cut a release, tag a commit on `main` and push the tag:

```bash
git tag -a v2.0.0 -m "bizzymod-stats 2.0.0"
git push origin v2.0.0
```

`.github/workflows/release.yml` then:

1. Builds the plugin via sourceknight.
2. Stages a release tree:

   ```
   bizzymod-stats-<version>/
   ├── addons/sourcemod/
   │   ├── plugins/bizzymod_stats.smx
   │   ├── gamedata/bizzymod_stats.txt
   │   ├── translations/bizzymod_stats.phrases.txt
   │   └── configs/bizzymod_stats/{databases,bizzymod_stats}.cfg.example
   ├── schema/
   │   ├── migrations/mysql/*.sql
   │   ├── migrate.py
   │   ├── install.sh
   │   └── requirements.txt
   ├── source.tar.gz
   ├── README.md
   ├── INSTALL.md
   └── LICENSE
   ```

3. Zips it, generates a changelog from `git log <prev-tag>..HEAD`, and
   uploads to a GitHub Release.

Versions containing a hyphen (e.g. `v2.1.0-rc1`) are marked as
pre-releases automatically.

**Version policy:**

- **MAJOR** — breaking schema changes that need data migration or
  databases.cfg renames.
- **MINOR** — new stats, awards, commands. Forward-compatible additive
  migrations only.
- **PATCH** — bug fixes, CVar default tweaks, doc updates.

---

## What is captured

Full event-to-column map lives in [`docs/STATS.md`](docs/STATS.md).
Headline coverage:

### Combat
Kills (by type — common / special / tank / witch / melee / survivor),
shots fired/hit, headshots, damage dealt/taken/friendly, damage to
tank/witch/special breakdowns, throwable usage (pipe/molotov/bile thrown
+ kills + burn damage attribution), per-weapon stats.

### Survivor support
Revives, defib uses, medkit-other, pills/adrenaline given, gas pours,
ammo upgrades, saves from each SI pin type, witch crowner.

### Infected detail (per SI)
Spawn count, playtime, pounces (perfect/nice), vomits, blinds, rides,
ride time, impacts, scattering rams, bulldozers, tank punches/rocks,
spitter pools.

### Game flow
Maps completed, campaigns finished, round wins/losses, mission lost.

### Discipline (negative)
Friendly fire incidents, friendly damage, teamkills, car alarms triggered.

### Pin tracking (from victim's POV)
Pinned by smoker/hunter/jockey/charger counts, vomited-on count,
self-escape count.

### Time-based
Time alive, time dead, time incapped, time on team, distance travelled.

### Career bests
Most points/kills/headshots in a session, biggest tank punch, longest
kill streak, longest jockey ride, fastest finale.

### Versus / Realism Versus / Scavenge (the big one)
See [`docs/VERSUS.md`](docs/VERSUS.md) for the deep dive. Captures match
boundaries (one campaign play with stable teams), per-map winners (both
team scores), per-half (round) outcomes with both **engine score**
(authoritative, distance-based) and **plugin score** (sum of points),
per-player per-half MVP data, persistent team identity across side
swaps, voluntary swap detection, win/loss/streak rollups.

---

## ConVar reference

Full reference: [`docs/CVARS.md`](docs/CVARS.md).

### Master switches
| ConVar                          | Default | Purpose                                     |
|---------------------------------|---------|---------------------------------------------|
| `bizzymod_stats_enabled`            | `1`     | 0 disables all stat collection             |
| `bizzymod_stats_announce_join`      | `1`     | Print joining player's rank to chat        |
| `bizzymod_stats_announce_rank`      | `1`     | Announce rank changes                      |
| `bizzymod_stats_negative_score`     | `1`     | Allow point losses                         |
| `bizzymod_stats_difficulty_multiplier` | `1`  | Scale by difficulty multiplier             |
| `bizzymod_stats_log_events`         | `0`     | Write `award_events` firehose              |

### Friendly fire
| ConVar                          | Default | Purpose                                     |
|---------------------------------|---------|---------------------------------------------|
| `bizzymod_stats_ffire_mode`         | `1`     | 0=off, 1=cooldown, 2=damage-based         |
| `bizzymod_stats_ffire_multiplier`   | `1.5`   | Damage-mode: penalty = damage × multiplier |
| `bizzymod_stats_ffire_cooldown`     | `10.0`  | Cooldown-mode: seconds between incidents   |

### Tunables read on-demand (no pre-registration)
These are looked up via `FindConVar` when the relevant event fires; set
them in your `cfg/sourcemod/bizzymod_stats.cfg` and they take effect
immediately.

| ConVar                                | Default | Purpose                          |
|---------------------------------------|---------|----------------------------------|
| `bizzymod_stats_survivor_incap`           | `15`    | Points for incap-as-infected     |
| `bizzymod_stats_survivor_death`           | `40`    | Points for kill-as-infected      |
| `bizzymod_stats_witch_kill`               | `20`    | Survivor witch kill              |
| `bizzymod_stats_common_kill`              | `1`     | Common infected kill             |
| `bizzymod_stats_pounce_perfect_damage`    | `25`    | Perfect pounce threshold         |
| `bizzymod_stats_pounce_nice_damage`       | `15`    | Nice pounce threshold            |
| `bizzymod_stats_scatter_ram_hits`         | `4`     | Charger scattering-ram threshold |
| `bizzymod_stats_heal_other`               | `10`    | Medkit on teammate               |
| `bizzymod_stats_ff_base_penalty`          | `25`    | Cooldown-mode FF penalty/event   |
| `bizzymod_stats_burn`                     | `1`     | Per zombie-ignited point         |

---

## Commands

### Players

| Command                  | Purpose                                            |
|--------------------------|----------------------------------------------------|
| `sm_rank`                | Show your rank and points                         |
| `sm_top10`               | Top 10 by points                                  |
| `sm_top10ppm`            | Top 10 by points-per-minute                       |
| `sm_nextrank`            | Points needed to climb to next rank               |
| `sm_showrank`            | Show ranks for everyone online                    |
| `sm_rankmenu`            | Open the stats menu                               |
| `sm_rankmute <0\|1>`     | Mute/unmute stat-related chat                     |
| `sm_rankmutetoggle`      | Toggle stat-related chat mute                     |
| `sm_showmotd`            | Show the server's MOTD                            |
| `sm_rankvote`            | Initiate a vote to shuffle teams by PPM (versus only) |

### Admins

| Command                  | Flag    | Purpose                                       |
|--------------------------|---------|-----------------------------------------------|
| `sm_rank_shuffle`        | `KICK`  | Force-shuffle teams by PPM                    |
| `sm_rank_motd <text>`    | `GENERIC` | Update the server MOTD                      |
| `sm_rank_clear`          | `ROOT`  | Wipe all stats (asks for 10-second confirmation) |

---

## Troubleshooting

### Plugin SetFailStates: "cannot connect to 'bizzymod_stats' database"

Your `databases.cfg` entry is missing, wrong, or the DB isn't reachable.

```bash
# Test from the game server's host:
mysql -h db.internal -u bizzymod_stats -p bizzymod_stats -e "SELECT 1"
```

If that works but the plugin fails, double-check the entry name is
**exactly** `bizzymod_stats` (the hard-coded name). It is case-sensitive.

### Plugin loads but no rows appear in `players`

Check `addons/sourcemod/logs/errors_<date>.log` for `[bizzymod-stats]` lines.
Common causes:

- The server connected to the DB but `INSERT` privileges are missing.
  Re-run the `GRANT ALL ON bizzymod_stats.*` from step 1.
- The schema is missing/incomplete. Re-run `migrate.py`.
- All connecting clients are fake clients (bots) — bizzymod-stats does not
  track bots.

### Versus rounds show zero `engine_score`

The plugin failed to read the `terror_player_manager.m_iCampaignScore`
netprop. This happens on some custom engine builds. The plugin falls
back to using `plugin_score_surv` to decide the winner — functional but
doesn't match what the in-game scoreboard shows. Confirm via:

```sql
SELECT round_index, engine_score, plugin_score_surv, end_reason
FROM match_rounds ORDER BY id DESC LIMIT 5;
```

If `engine_score` is consistently 0 but `plugin_score_surv` is non-zero,
you're hitting this fallback. File an issue with your engine version.

### The "nested comment" warning during compile

Harmless. SourceMod's compiler warns when a doc comment contains `/*`.
We have one such pattern in a `// comment` string — it's a false-positive.

### Player names show as `NULL` or `???` in the web UI

The `players.name` column is `VARBINARY` (raw bytes) to survive
non-UTF8 game nicknames. The web stub casts with `CAST(name AS CHAR)`
which is fine for ASCII names. For non-ASCII nicknames you'll see
replacement characters. Future web-tier work should detect the
encoding per-row.

### Match listed as `abandoned` when I know I finished it

The plugin marks any match as abandoned on shutdown if its `ended_at`
is still NULL. This happens if:

- The server restarted mid-match.
- The plugin was unloaded mid-match.
- `OnMapStart` fired with a different campaign before
  `versus_match_finished` had a chance to fire.

The granular `match_rounds`/`match_maps` data is still intact and
correct — only the top-level `matches.winner` says `abandoned`.

---

## Extending bizzymod-stats

### Adding a new tracked stat

1. **Choose its home** — rollup column on `player_stats`, per-SI on
   `player_si_stats`, per-weapon on `player_weapon_stats`, per-round on
   `player_round_stats`, or new award in `awards`.
2. **Write a migration** at `schema/migrations/mysql/008_my_stat.sql`
   with `ALTER TABLE ... ADD COLUMN` (or `INSERT INTO awards`).
3. **Add a field** to `ClientState` in
   `plugin/scripting/include/bizzymod_stats.inc` (if it's a per-session
   counter).
4. **Reset it** in `Bizzy_ResetClientState()` (`util.sp`).
5. **Capture it** — find the right event in `events.sp` and increment
   the field.
6. **Flush it** — extend the SQL in `Bizzy_Session_Flush()`
   (`session.sp`) to include the new column.

Recompile, redeploy, and your new stat is live.

### Adding a new award

1. `INSERT INTO awards (code, name, ...) VALUES (...)` in a new migration.
2. Call `Bizzy_Awards_Fire(client, "your_code", 1)` from anywhere in the
   plugin that should trigger the award.

That's the whole loop — no plugin recompile is required if the trigger
point already exists.

### Adding a new game mode

1. `INSERT INTO gamemodes (id, code, name)` in a new migration.
   Pick an ID that doesn't conflict (current range: 0–8).
2. Add a matching enum value to `GameMode` in
   `plugin/scripting/include/bizzymod_stats.inc`.
3. Extend `Bizzy_DetectGameMode()` in `util.sp` to map the `mp_gamemode`
   string to your new enum value.

### Custom award trigger from another plugin

Other SourceMod plugins can fire bizzymod-stats awards by writing directly
to `player_awards`:

```sql
INSERT INTO player_awards (player_id, award_id, gamemode_id, count, first_at, last_at)
SELECT p.id, a.id, 0, 1, NOW(), NOW()
FROM players p, awards a
WHERE p.steamid = 'STEAM_X:Y:Z' AND a.code = 'your_code'
ON DUPLICATE KEY UPDATE count = count + 1, last_at = NOW();
```

This is the recommended integration path — no native, no forwards, just
a shared schema.

---

## Repository layout

```
bizzymod-stats/
├── plugin/                      # SourcePawn source for the plugin
│   ├── scripting/
│   │   ├── bizzymod_stats.sp         # main entry; orchestrates modules
│   │   ├── include/
│   │   │   └── bizzymod_stats.inc    # shared types, ClientState struct
│   │   └── bizzymod_stats/           # one .sp per concern
│   │       ├── util.sp          # helpers (no global state writes)
│   │       ├── config.sp        # ConVar registration
│   │       ├── database.sp      # async DB wrapper
│   │       ├── identity.sp      # players/servers/maps resolution
│   │       ├── session.sp       # session lifecycle + flush
│   │       ├── scoring.sp       # central Bizzy_Score()
│   │       ├── awards.sp        # award catalog + persistence
│   │       ├── weapons.sp       # weapon stat capture
│   │       ├── events.sp        # game event hooks
│   │       ├── timedmaps.sp     # map timing
│   │       ├── versus.sp        # match/round/team tracking
│   │       ├── rankvote.sp      # team-shuffle vote
│   │       ├── motd.sp          # MOTD
│   │       └── commands.sp      # player/admin commands
│   ├── gamedata/
│   │   └── bizzymod_stats.txt        # engine signatures for L4D1+L4D2
│   ├── translations/
│   │   └── bizzymod_stats.phrases.txt
│   └── configs/
│       ├── databases.cfg.example
│       └── bizzymod_stats.cfg.example
│
├── schema/                      # MySQL schema + migrations
│   ├── migrations/mysql/
│   │   ├── 001_init_schema.sql       # catalogs + identity + sessions
│   │   ├── 002_stat_tables.sql       # rollup stat tables
│   │   ├── 003_awards.sql            # awards catalog + player_awards
│   │   ├── 004_seed_catalogs.sql     # initial games/modes/awards/weapons
│   │   ├── 005_views.sql             # convenience views
│   │   ├── 006_versus_rounds.sql     # match/round/team tracking
│   │   └── 007_extended_stats.sql    # throwables, time, pins, bests
│   └── scripts/
│       ├── migrate.py                # forward-only migration runner
│       ├── install.sh                # bash one-liner installer
│       ├── install.ps1               # PowerShell equivalent
│       └── requirements.txt
│
├── web/                         # PHP 8 / PDO stub front-end
│   ├── public/
│   │   ├── index.php            # top players
│   │   ├── matches.php          # versus match list
│   │   ├── match.php            # single match detail
│   │   ├── player.php           # single player profile
│   │   ├── awards.php           # award leaderboards
│   │   └── server.php           # server list + sessions
│   ├── src/{Db,View}.php
│   ├── templates/layout.phtml
│   └── config.example.php
│
├── docs/                        # in-depth design + reference
│   ├── ARCHITECTURE.md          # how the components interact
│   ├── DATABASE.md              # schema tour + why-normalized
│   ├── STATS.md                 # every captured stat, event-to-column
│   ├── VERSUS.md                # versus/match/round design deep-dive
│   ├── CVARS.md                 # full CVar reference
│   ├── INSTALL.md               # condensed install guide
│   ├── RELEASE.md               # release process
│   └── ROADMAP.md               # what we could add next
│
├── .github/
│   ├── workflows/
│   │   ├── ci.yml               # build + MySQL schema validation
│   │   └── release.yml          # tag-triggered release packaging
│   └── dependabot.yml
│
├── legacy/                      # the 2010-2015 forked codebase, preserved
│   ├── bizzymod_stats.sp.v1.5        # 339KB pre-rewrite SourcePawn
│   ├── l4d2stats.legacy.sql     # 200KB Navicat dump
│   ├── bizzymod_stats.gamedata.legacy.txt
│   ├── README.forumpost.md      # the original AlliedModders thread
│   └── web/                     # 2013-era PHP w/ deprecated mysql_*
│
├── sourceknight.yaml            # build orchestrator config
├── CLAUDE.md                    # guidance for Claude Code / future contributors
└── README.md                    # this file
```

---

## Versus / round tracking deep dive

The most novel part of bizzymod-stats is its versus match tracking. Each
match is a contiguous campaign play with stable teams. Within a match,
each map has two halves (rounds): one team plays Survivors, the other
plays Infected; they swap for the second half. Per-map winner = whichever
team scored higher *as Survivors* over both halves combined. Match
winner = whichever team has higher cumulative score across all maps.

The tricky part is **persistent team identity**. The engine flips
players' GetClientTeam() between rounds — survivors become infected and
vice versa. bizzymod-stats maintains a `'A'` / `'B'` letter per player that
survives this flip but **does** update on voluntary `jointeam` swaps
(detected by `team_changed` event firing *during* an active round, vs.
between rounds which is when the engine flips).

Each round stores two scores:

- **`engine_score`** — what L4D2's `m_iCampaignScore` netprop reports,
  i.e. the distance-based scenario score the game uses to declare the
  winner. This is what your players see on the scoreboard.
- **`plugin_score_surv`** / **`plugin_score_inf`** — sum of all
  bizzymod-stats points (kills, awards, etc.) by team this round. Useful for
  MVP-of-round and PPM, not used to decide the winner.

The full schema for versus tracking lives in migration 006 and the
implementation in `plugin/scripting/bizzymod_stats/versus.sp`. See
[`docs/VERSUS.md`](docs/VERSUS.md) for vocabulary, the team-letter
problem in depth, queries you'll actually want to run, and known
limitations.

---

## License & credits

GPL-3.0-or-later. See [`LICENSE`](LICENSE).

Based on "Custom Player Stats" v1.5 by Mikko Andersson (muukis), itself
derived from earlier work by msleeper. The original plugin was released
under GPLv3 on AlliedModders. The pre-rewrite codebase is preserved
untouched under `legacy/` — see `legacy/README.forumpost.md` for the
authoritative reference on the historical scoring formulas and CVars.
