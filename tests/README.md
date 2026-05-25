# tests

Bash-driven harness covering compile, migrations, seed sanity, FK integrity
and view sanity.

## Run locally

```bash
./tests/run.sh
```

Prerequisites: `docker`, `python3 + pymysql` (`pip install pymysql`), and
either `SPCOMP=...` + `SM_INCLUDE=...` env vars pointing at a SourceMod
1.12 toolchain, or none — the script will auto-download the toolchain to
`tests/.sm-toolchain/` on first run.

## In CI

`.github/workflows/ci.yml` invokes this script on the self-hosted runner.
The runner only needs the prerequisites above to be installed once.

## What it tests

1. Plugin compiles with zero errors via `spcomp64`.
2. All 14 migrations apply to a fresh `bizzymod_stats_test` database.
3. Re-running the runner is a no-op (idempotency).
4. Catalog tables (`games`, `gamemodes`, `difficulties`, `special_infected`,
   `survivors`, `awards`, `weapons`) have at least the expected seed counts.
5. Sampled foreign-key constraints reject invalid inserts.
6. All convenience views are queryable.

Exit code 0 on success, non-zero on any failure. The MySQL container is
removed via `trap cleanup EXIT` regardless of outcome.
