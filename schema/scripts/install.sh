#!/usr/bin/env bash
# Bootstrap a fresh bizzymod-stats database. Requires a MySQL user with CREATE
# DATABASE permission. Usage:
#
#   ./install.sh [--db NAME] [--user USER] [--host HOST] [--port PORT]
#
# Prompts for the MySQL admin password if not in MYSQL_PWD env.
set -euo pipefail

DB_NAME="bizzymod_stats"
DB_USER="root"
DB_HOST="127.0.0.1"
DB_PORT="3306"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)   DB_NAME="$2"; shift 2 ;;
        --user) DB_USER="$2"; shift 2 ;;
        --host) DB_HOST="$2"; shift 2 ;;
        --port) DB_PORT="$2"; shift 2 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "Creating database '${DB_NAME}' on ${DB_HOST}:${DB_PORT} as ${DB_USER}..."
mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p \
    -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

echo "Applying migrations..."
python3 "${SCRIPT_DIR}/migrate.py" \
    --host "${DB_HOST}" --port "${DB_PORT}" \
    --user "${DB_USER}" \
    --database "${DB_NAME}"

echo "Done. Next steps:"
echo "  1. Add a databases.cfg entry named 'bizzymod_stats' on the game server."
echo "  2. Drop bizzymod_stats.smx into addons/sourcemod/plugins/."
echo "  3. Restart the server (or 'sm plugins load bizzymod_stats')."
