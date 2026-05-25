# Bootstrap a fresh bizzymod-stats database on Windows.
#
# Requires: mysql.exe and python3 in PATH, pymysql installed.
# Usage:
#   .\install.ps1 -Database bizzymod_stats -User root -Host 127.0.0.1 -Port 3306

param(
    [string]$Database = "bizzymod_stats",
    [string]$DbUser   = "root",
    [string]$DbHost   = "127.0.0.1",
    [int]   $Port     = 3306
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Creating database '$Database' on ${DbHost}:${Port} as $DbUser..."
$createSql = "CREATE DATABASE IF NOT EXISTS ``$Database`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
& mysql -h $DbHost -P $Port -u $DbUser -p -e $createSql
if ($LASTEXITCODE -ne 0) { throw "mysql create-database failed (exit $LASTEXITCODE)" }

Write-Host "Applying migrations..."
& python "$scriptDir\migrate.py" `
    --host $DbHost --port $Port --user $DbUser --database $Database
if ($LASTEXITCODE -ne 0) { throw "migrate.py failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "Done. Next steps:"
Write-Host "  1. Add a databases.cfg entry named 'bizzymod_stats' on the game server."
Write-Host "  2. Drop bizzymod_stats.smx into addons/sourcemod/plugins/."
Write-Host "  3. Restart the server (or 'sm plugins load bizzymod_stats')."
