#!/usr/bin/env bash
# bizzymod-stats test harness.
#
# Runs:
#   - SQL migrations applied to a fresh MySQL 8 container
#   - Idempotency check (re-apply emits no changes)
#   - Catalog-seed sanity
#   - FK integrity probe
#   - SourcePawn plugin compile
#
# Requirements on the host:
#   - docker
#   - python3 + pymysql
#   - spcomp64 + the SourceMod 1.12 include set, either:
#       * SPCOMP=/path/to/spcomp64 SM_INCLUDE=/path/to/sourcemod/scripting/include
#       * or auto-downloaded to tests/.sm-toolchain on first run
#
# Exit code: 0 on success, non-zero if any test fails.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTAINER="bizzy-mysql-tests"
PORT="${BIZZY_TEST_MYSQL_PORT:-33399}"

cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
hdr()  { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

# Pick a working python — on Windows `python3` often resolves to the
# Microsoft Store stub which prints an error instead of running. Probe.
PYTHON=""
for candidate in python3 python python3.12 python3.11 python3.10; do
    if command -v "$candidate" >/dev/null 2>&1 \
       && "$candidate" -c "import sys; sys.exit(0)" >/dev/null 2>&1; then
        PYTHON="$candidate"; break
    fi
done
[[ -n "$PYTHON" ]] || fail "no working python interpreter found"

# ----------------------------------------------------------------------------
# 1. Plugin compile
# ----------------------------------------------------------------------------
hdr "Plugin compile"

SPCOMP="${SPCOMP:-}"
SM_INCLUDE="${SM_INCLUDE:-}"

if [[ -z "$SPCOMP" || -z "$SM_INCLUDE" ]]; then
    TOOLCHAIN="$SCRIPT_DIR/.sm-toolchain"
    if [[ ! -x "$TOOLCHAIN/sm/addons/sourcemod/scripting/spcomp64.exe"
        && ! -x "$TOOLCHAIN/sm/addons/sourcemod/scripting/spcomp64" ]]; then
        echo "  fetching SourceMod 1.12 toolchain to $TOOLCHAIN..."
        mkdir -p "$TOOLCHAIN"
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*) SM_URL="https://sm.alliedmods.net/smdrop/1.12/sourcemod-1.12.0-git7210-windows.zip" ;;
            Linux*)               SM_URL="https://sm.alliedmods.net/smdrop/1.12/sourcemod-1.12.0-git7210-linux.tar.gz" ;;
            Darwin*)              SM_URL="https://sm.alliedmods.net/smdrop/1.12/sourcemod-1.12.0-git7210-mac.tar.gz" ;;
            *)                    echo "  unsupported OS"; exit 1 ;;
        esac
        curl -sLo "$TOOLCHAIN/sm.archive" "$SM_URL"
        case "$SM_URL" in
            *.zip)        unzip -q "$TOOLCHAIN/sm.archive" -d "$TOOLCHAIN/sm" ;;
            *.tar.gz)     mkdir -p "$TOOLCHAIN/sm" && tar xzf "$TOOLCHAIN/sm.archive" -C "$TOOLCHAIN/sm" ;;
        esac
    fi
    if [[ -x "$TOOLCHAIN/sm/addons/sourcemod/scripting/spcomp64.exe" ]]; then
        SPCOMP="$TOOLCHAIN/sm/addons/sourcemod/scripting/spcomp64.exe"
    elif [[ -x "$TOOLCHAIN/sm/addons/sourcemod/scripting/spcomp64" ]]; then
        SPCOMP="$TOOLCHAIN/sm/addons/sourcemod/scripting/spcomp64"
    else
        SPCOMP="$TOOLCHAIN/sm/addons/sourcemod/scripting/spcomp"
    fi
    SM_INCLUDE="$TOOLCHAIN/sm/addons/sourcemod/scripting/include"
fi

mkdir -p "$ROOT/plugin/build"
if "$SPCOMP" -i"$SM_INCLUDE" -i"$ROOT/plugin/scripting" \
       "$ROOT/plugin/scripting/bizzymod_stats.sp" \
       -o"$ROOT/plugin/build/bizzymod_stats.smx" 2>&1 | tee "$SCRIPT_DIR/.compile.log" \
       | grep -E '^[0-9]+ Error' | grep -vq '^0 Errors'; then
    # If grep matched a non-zero error count line we'd be in this branch; the
    # inverse logic (no errors line) is the normal pass.
    :
fi
if grep -qE '^[1-9][0-9]* Errors' "$SCRIPT_DIR/.compile.log"; then
    cat "$SCRIPT_DIR/.compile.log"
    fail "plugin failed to compile"
fi
if [[ ! -s "$ROOT/plugin/build/bizzymod_stats.smx" ]]; then
    fail ".smx not produced"
fi
SIZE=$(stat -c%s "$ROOT/plugin/build/bizzymod_stats.smx" 2>/dev/null || stat -f%z "$ROOT/plugin/build/bizzymod_stats.smx")
pass "compiled bizzymod_stats.smx ($SIZE bytes)"

# ----------------------------------------------------------------------------
# 2. MySQL container + migrations
# ----------------------------------------------------------------------------
hdr "MySQL container"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run --rm -d --name "$CONTAINER" \
    -e MYSQL_ROOT_PASSWORD=test -e MYSQL_DATABASE=bizzymod_stats_test \
    -p "$PORT:3306" mysql:8.0 >/dev/null

for i in {1..60}; do
    if docker exec "$CONTAINER" mysql -uroot -ptest -e "SELECT 1" bizzymod_stats_test \
            >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
docker exec "$CONTAINER" mysql -uroot -ptest -e "SELECT 1" bizzymod_stats_test \
    >/dev/null 2>&1 || fail "mysql never came up"
pass "MySQL 8.0 reachable on port $PORT"

# ----------------------------------------------------------------------------
# 3. Migrations apply
# ----------------------------------------------------------------------------
hdr "Migrations"
$PYTHON "$ROOT/schema/scripts/migrate.py" \
    --host 127.0.0.1 --port "$PORT" \
    --user root --password test \
    --database bizzymod_stats_test > "$SCRIPT_DIR/.migrate.log" 2>&1 \
    || { cat "$SCRIPT_DIR/.migrate.log"; fail "migrations failed"; }
COUNT=$(grep -c "applied\." "$SCRIPT_DIR/.migrate.log" || true)
[[ "$COUNT" -eq 14 ]] || fail "expected 14 migrations, applied $COUNT"
pass "$COUNT migrations applied"

# ----------------------------------------------------------------------------
# 4. Idempotency
# ----------------------------------------------------------------------------
hdr "Idempotency"
$PYTHON "$ROOT/schema/scripts/migrate.py" \
    --host 127.0.0.1 --port "$PORT" \
    --user root --password test \
    --database bizzymod_stats_test > "$SCRIPT_DIR/.migrate2.log" 2>&1
grep -q "up to date" "$SCRIPT_DIR/.migrate2.log" \
    || { cat "$SCRIPT_DIR/.migrate2.log"; fail "second apply should be a no-op"; }
pass "second apply is a no-op"

# ----------------------------------------------------------------------------
# 5. Seed sanity
# ----------------------------------------------------------------------------
hdr "Seed sanity"
mysql() { docker exec -e MYSQL_PWD=test "$CONTAINER" mysql -uroot -N -B "$@"; }

check_count() {
    local table="$1" expected="$2"
    local got=$(mysql bizzymod_stats_test -e "SELECT COUNT(*) FROM $table")
    [[ "$got" -ge "$expected" ]] || fail "expected $table >= $expected rows, got $got"
    pass "$table: $got rows"
}

check_count games            3
check_count gamemodes        9
check_count difficulties     5
check_count special_infected 8
check_count survivors        8
check_count awards          80
check_count weapons         40

# ----------------------------------------------------------------------------
# 6. FK integrity probe
# ----------------------------------------------------------------------------
hdr "FK integrity"

# Pick a sampling of FK-constrained inserts that should fail.
expect_fail() {
    local descr="$1" sql="$2"
    if mysql bizzymod_stats_test -e "$sql" >/dev/null 2>&1; then
        fail "FK should have rejected: $descr"
    fi
    pass "FK rejects: $descr"
}

expect_fail "match_teams w/ unknown match_id" \
    "INSERT INTO match_teams (match_id, team_letter) VALUES (999999, 'A')"
expect_fail "player_stats w/ unknown gamemode" \
    "INSERT INTO player_stats (player_id, gamemode_id, difficulty_id, server_id) VALUES (1, 99, 0, 0)"
expect_fail "session w/ unknown server" \
    "INSERT INTO sessions (player_id, server_id, gamemode_id, difficulty_id, started_at) VALUES (1, 99999, 0, 0, NOW())"

# ----------------------------------------------------------------------------
# 7. View sanity
# ----------------------------------------------------------------------------
hdr "Views compile and select"
for v in v_top_players v_player_totals v_match_summary v_player_versus \
         v_player_ttk v_match_score_curve v_career_bests v_player_health; do
    mysql bizzymod_stats_test -e "SELECT * FROM $v LIMIT 0" >/dev/null 2>&1 \
        || fail "view $v not queryable"
    pass "view $v selectable"
done

hdr "All tests passed"
