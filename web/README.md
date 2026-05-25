# bizzymod-stats web (stub)

A minimal PHP 8 / PDO front-end against the bizzymod-stats database. Intentionally
sparse — its job is to prove the schema works end-to-end and serve as a
template for future refinement.

The legacy web stats from "Custom Player Stats" live under `../legacy/web/`
and are unmaintained. Do not edit them.

## Pages

- `/`              — top players (uses `v_top_players` view)
- `/player.php?id=N` — single-player profile (totals + awards + per-gamemode)
- `/server.php?id=N` — per-server summary
- `/awards.php`    — award leaderboards

## Run locally

```
cp config.example.php config.php   # edit DB creds
php -S 127.0.0.1:8080 -t public
```

Requires PHP 8.1+ with `pdo_mysql`.
