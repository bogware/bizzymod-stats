# Install

End-to-end walkthrough for a fresh install on a Linux SRCDS / MySQL host.
For Windows hosts the SourceMod steps are identical; use `install.ps1`
instead of `install.sh` for the DB step.

## 1. MySQL

You need a MySQL 8 (or 5.7+) server reachable from both the web host
and the game server.

```bash
sudo mysql -u root -p
```

```sql
CREATE DATABASE bizzymod_stats CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'bizzymod_stats'@'%' IDENTIFIED BY 'STRONG-PASSWORD';
GRANT ALL ON bizzymod_stats.* TO 'bizzymod_stats'@'%';
FLUSH PRIVILEGES;
```

Apply the migrations:

```bash
git clone https://github.com/<you>/bizzymod-stats.git
cd bizzymod-stats/schema/scripts
pip install -r requirements.txt
python migrate.py \
  --host db.internal --user bizzymod_stats --password STRONG-PASSWORD \
  --database bizzymod_stats
```

You should see all `001_…` through `005_…` migrations applied and
"Database is up to date" on the second run.

## 2. SourceMod plugin

Download a release zip from the [Releases](../../releases) page.

Extract into your L4D2 `left4dead2/` directory (or L4D1's `left4dead/`):

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

Merge the database example into your real `databases.cfg`:

```
left4dead2/addons/sourcemod/configs/databases.cfg
```

You must have an entry named **exactly `bizzymod_stats`**:

```
"Databases"
{
    "default" { ... }
    "bizzymod_stats"
    {
        "driver"   "mysql"
        "host"     "db.internal"
        "database" "bizzymod_stats"
        "user"     "bizzymod_stats"
        "pass"     "STRONG-PASSWORD"
        "port"     "3306"
    }
}
```

Copy the cvar defaults if you want them in source control:

```bash
cp configs/bizzymod_stats/bizzymod_stats.cfg.example  cfg/sourcemod/bizzymod_stats.cfg
```

Restart the server (or `sm plugins load bizzymod_stats`).

Check the log:

```
[bizzymod-stats] online as server_id=1 (key=<32-hex>)
```

If you see `cannot connect to 'bizzymod_stats' database`, your databases.cfg
entry is wrong or unreachable. The plugin SetFailState's intentionally —
silent stat loss is worse than a loud failure.

## 3. Web (optional)

Requires PHP 8.1+ with `pdo_mysql`.

```bash
cd web
cp config.example.php config.php
# edit DB creds in config.php
php -S 127.0.0.1:8080 -t public
```

Open `http://127.0.0.1:8080`. You should see an (empty) top-players
leaderboard. Play a round of L4D2 and refresh.

For production, point an nginx/apache document root at `web/public/`.

## 4. Verification

After at least one round of play:

```sql
SELECT COUNT(*) FROM players;       -- > 0
SELECT COUNT(*) FROM sessions;      -- > 0
SELECT COUNT(*) FROM player_stats;  -- > 0
SELECT * FROM v_top_players LIMIT 5;
```

If those return data and the web page renders it, you're set.
