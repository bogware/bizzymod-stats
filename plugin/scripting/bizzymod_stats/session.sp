/**
 * session.sp — per-player session lifecycle.
 *
 * A session = one continuous (player, server) presence. We open one on
 * client auth completion, flush rollups + close it on disconnect or map
 * change. The in-memory per-client counters in ClientState aggregate
 * during the session and are flushed in one transaction at close.
 */

void Bizzy_OnSessionInit() { /* nothing yet */ }

stock void Bizzy_BeginClientSession(int client)
{
    if (!Bizzy_IsValidPlayer(client)) return;
    if (g_Clients[client].inUse) return;

    g_Clients[client].inUse            = true;
    g_Clients[client].sessionStartTime = Bizzy_NowEpoch();
    g_Clients[client].team             = GetClientTeam(client);

    // ResolvePlayer -> Session_Open chains via callbacks; we just kick it off.
    Bizzy_Identity_ResolvePlayer(client);
}

stock void Bizzy_Session_Open(int client)
{
    if (!Bizzy_IsValidPlayer(client) || g_Clients[client].playerId == 0)
        return;
    if (g_Clients[client].sessionId != 0) return;

    char sql[512];
    FormatEx(sql, sizeof sql,
        "INSERT INTO sessions (player_id, server_id, gamemode_id, difficulty_id, map_id, started_at, team) "
        ... "VALUES (%d, %d, %d, %d, NULLIF(%d, 0), NOW(), %d)",
        g_Clients[client].playerId, g_ServerId,
        view_as<int>(g_CurrentMode), view_as<int>(g_CurrentDifficulty),
        g_CurrentMapId, g_Clients[client].team);

    DataPack dp = new DataPack();
    dp.WriteCell(GetClientUserId(client));
    g_DB.Query(OnSessionInserted, sql, dp);

    if (g_cvAnnounceJoin.BoolValue && !g_Clients[client].muted)
        AnnounceJoiningPlayer(client);
}

static void OnSessionInserted(Database db, DBResultSet rs, const char[] error, DataPack dp)
{
    dp.Reset();
    int uid = dp.ReadCell();
    delete dp;
    if (error[0] != '\0') { LogError("[bizzymod-stats] session insert: %s", error); return; }
    int client = GetClientOfUserId(uid);
    if (client == 0) return;
    g_Clients[client].sessionId = rs.InsertId;
}

stock void Bizzy_EndClientSession(int client)
{
    if (!g_Clients[client].inUse) return;
    int duration = Bizzy_NowEpoch() - g_Clients[client].sessionStartTime;
    if (duration < 0) duration = 0;

    Bizzy_Session_Flush(client, duration);
    Bizzy_ResetClientState(client);
}

/**
 * Flush in-memory counters to player_stats + close the open session row.
 * Atomic per-client transaction.
 */
stock void Bizzy_Session_Flush(int client, int duration)
{
    if (g_DB == null || g_Clients[client].playerId == 0) return;

    Transaction txn = Bizzy_DB_BeginTxn();

    // Final time-alive: if still alive, add the trailing span.
    if (g_Clients[client].aliveSinceEpoch != 0)
    {
        int alive = Bizzy_NowEpoch() - g_Clients[client].aliveSinceEpoch;
        if (alive > 0) g_Clients[client].timeAliveS += alive;
        g_Clients[client].aliveSinceEpoch = 0;
    }
    // Final kill-streak peak
    if (g_Clients[client].killStreak > g_Clients[client].killStreakMax)
        g_Clients[client].killStreakMax = g_Clients[client].killStreak;

    // 1) Upsert rollup row in player_stats.
    char sql[2048];
    FormatEx(sql, sizeof sql,
        "INSERT INTO player_stats "
        ... "(player_id, gamemode_id, difficulty_id, server_id, "
        ... " points, playtime_s, sessions, "
        ... " shots_fired, shots_hit, headshots, "
        ... " damage_dealt, damage_taken, damage_friendly, "
        ... " kills_common, incaps, deaths, "
        ... " pipe_bombs_thrown, pipe_bombs_kills, "
        ... " molotovs_thrown, molotovs_kills, molotov_burn_damage, "
        ... " bile_bombs_thrown, bile_bombs_hits, "
        ... " damage_to_tank, damage_to_witch, damage_to_special, "
        ... " time_alive_s, time_dead_s, time_incapped_s, "
        ... " pinned_by_smoker, pinned_by_hunter, pinned_by_jockey, pinned_by_charger, "
        ... " vomited_on, self_escapes, distance_units) "
        ... "VALUES (%d, %d, %d, 0, "
        ... " %d, %d, 1, "
        ... " %d, %d, %d, "
        ... " %d, %d, %d, "
        ... " %d, %d, %d, "
        ... " %d, %d, "
        ... " %d, %d, %d, "
        ... " %d, %d, "
        ... " %d, %d, %d, "
        ... " %d, %d, %d, "
        ... " %d, %d, %d, %d, "
        ... " %d, %d, %d) "
        ... "ON DUPLICATE KEY UPDATE "
        ... " points              = points              + VALUES(points), "
        ... " playtime_s          = playtime_s          + VALUES(playtime_s), "
        ... " sessions            = sessions            + 1, "
        ... " shots_fired         = shots_fired         + VALUES(shots_fired), "
        ... " shots_hit           = shots_hit           + VALUES(shots_hit), "
        ... " headshots           = headshots           + VALUES(headshots), "
        ... " damage_dealt        = damage_dealt        + VALUES(damage_dealt), "
        ... " damage_taken        = damage_taken        + VALUES(damage_taken), "
        ... " damage_friendly     = damage_friendly     + VALUES(damage_friendly), "
        ... " kills_common        = kills_common        + VALUES(kills_common), "
        ... " incaps              = incaps              + VALUES(incaps), "
        ... " deaths              = deaths              + VALUES(deaths), "
        ... " pipe_bombs_thrown   = pipe_bombs_thrown   + VALUES(pipe_bombs_thrown), "
        ... " pipe_bombs_kills    = pipe_bombs_kills    + VALUES(pipe_bombs_kills), "
        ... " molotovs_thrown     = molotovs_thrown     + VALUES(molotovs_thrown), "
        ... " molotovs_kills      = molotovs_kills      + VALUES(molotovs_kills), "
        ... " molotov_burn_damage = molotov_burn_damage + VALUES(molotov_burn_damage), "
        ... " bile_bombs_thrown   = bile_bombs_thrown   + VALUES(bile_bombs_thrown), "
        ... " bile_bombs_hits     = bile_bombs_hits     + VALUES(bile_bombs_hits), "
        ... " damage_to_tank      = damage_to_tank      + VALUES(damage_to_tank), "
        ... " damage_to_witch     = damage_to_witch     + VALUES(damage_to_witch), "
        ... " damage_to_special   = damage_to_special   + VALUES(damage_to_special), "
        ... " time_alive_s        = time_alive_s        + VALUES(time_alive_s), "
        ... " time_dead_s         = time_dead_s         + VALUES(time_dead_s), "
        ... " time_incapped_s     = time_incapped_s     + VALUES(time_incapped_s), "
        ... " pinned_by_smoker    = pinned_by_smoker    + VALUES(pinned_by_smoker), "
        ... " pinned_by_hunter    = pinned_by_hunter    + VALUES(pinned_by_hunter), "
        ... " pinned_by_jockey    = pinned_by_jockey    + VALUES(pinned_by_jockey), "
        ... " pinned_by_charger   = pinned_by_charger   + VALUES(pinned_by_charger), "
        ... " vomited_on          = vomited_on          + VALUES(vomited_on), "
        ... " self_escapes        = self_escapes        + VALUES(self_escapes), "
        ... " distance_units      = distance_units      + VALUES(distance_units)",
        g_Clients[client].playerId,
        view_as<int>(g_CurrentMode), view_as<int>(g_CurrentDifficulty),
        g_Clients[client].pointsThisSession, duration,
        g_Clients[client].shotsFired, g_Clients[client].shotsHit,
        g_Clients[client].headshots,
        g_Clients[client].damageDealt, g_Clients[client].damageTaken,
        g_Clients[client].damageFriendly,
        g_Clients[client].kills, g_Clients[client].incaps,
        g_Clients[client].deaths,
        g_Clients[client].pipeBombsThrown, g_Clients[client].pipeBombsKills,
        g_Clients[client].molotovsThrown, g_Clients[client].molotovsKills,
        g_Clients[client].molotovBurnDamage,
        g_Clients[client].bileBombsThrown, g_Clients[client].bileBombsHits,
        g_Clients[client].damageToTank, g_Clients[client].damageToWitch,
        g_Clients[client].damageToSpecial,
        g_Clients[client].timeAliveS, g_Clients[client].timeDeadS,
        g_Clients[client].timeIncappedS,
        g_Clients[client].pinnedBySmoker, g_Clients[client].pinnedByHunter,
        g_Clients[client].pinnedByJockey, g_Clients[client].pinnedByCharger,
        g_Clients[client].vomitedOn, g_Clients[client].selfEscapes,
        g_Clients[client].distanceUnits);
    txn.AddQuery(sql);

    // 1b) Career bests — single-row GREATEST update per player.
    FormatEx(sql, sizeof sql,
        "INSERT INTO career_bests "
        ... "(player_id, most_points_in_session, most_kills_in_session, "
        ... " most_headshots_in_session, longest_kill_streak, "
        ... " biggest_tank_punch_damage) "
        ... "VALUES (%d, %d, %d, %d, %d, %d) "
        ... "ON DUPLICATE KEY UPDATE "
        ... " most_points_in_session    = GREATEST(most_points_in_session,    VALUES(most_points_in_session)), "
        ... " most_kills_in_session     = GREATEST(most_kills_in_session,     VALUES(most_kills_in_session)), "
        ... " most_headshots_in_session = GREATEST(most_headshots_in_session, VALUES(most_headshots_in_session)), "
        ... " longest_kill_streak       = GREATEST(longest_kill_streak,       VALUES(longest_kill_streak)), "
        ... " biggest_tank_punch_damage = GREATEST(biggest_tank_punch_damage, VALUES(biggest_tank_punch_damage))",
        g_Clients[client].playerId,
        g_Clients[client].pointsThisSession,
        g_Clients[client].kills,
        g_Clients[client].headshots,
        g_Clients[client].killStreakMax,
        g_Clients[client].biggestTankPunch);
    txn.AddQuery(sql);

    // 2) Close the open session row.
    if (g_Clients[client].sessionId != 0)
    {
        FormatEx(sql, sizeof sql,
            "UPDATE sessions SET ended_at=NOW(), duration_s=%d, "
            ... "points=%d, kills=%d, deaths=%d WHERE id=%d",
            duration,
            g_Clients[client].pointsThisSession,
            g_Clients[client].kills, g_Clients[client].deaths,
            g_Clients[client].sessionId);
        txn.AddQuery(sql);
    }

    // 3) Update players.last_seen.
    FormatEx(sql, sizeof sql,
        "UPDATE players SET last_seen=NOW(), last_gamemode=%d WHERE id=%d",
        view_as<int>(g_CurrentMode), g_Clients[client].playerId);
    txn.AddQuery(sql);

    Bizzy_DB_RunTxn(txn);
}

stock void Bizzy_OnMapStart()
{
    Bizzy_Identity_ResolveMap();
}

stock void Bizzy_OnMapEnd()
{
    // Flush all open sessions; they reopen on next map.
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_Clients[i].inUse)
        {
            int duration = Bizzy_NowEpoch() - g_Clients[i].sessionStartTime;
            Bizzy_Session_Flush(i, duration);
            // Reset counters but keep `inUse` and steam/name; session will
            // reopen on OnMapStart via OnClientPostAdminCheck for hot-joiners
            // and via this loop on the next map for stayers.
            g_Clients[i].sessionId         = 0;
            g_Clients[i].sessionStartTime  = Bizzy_NowEpoch();
            g_Clients[i].pointsThisSession = 0;
            g_Clients[i].shotsFired = g_Clients[i].shotsHit = 0;
            g_Clients[i].headshots = 0;
            g_Clients[i].damageDealt = g_Clients[i].damageTaken = 0;
            g_Clients[i].damageFriendly = 0;
            g_Clients[i].kills = g_Clients[i].incaps = g_Clients[i].deaths = 0;
        }
    }
}

static void AnnounceJoiningPlayer(int client)
{
    if (g_Clients[client].playerId == 0) return;
    // Rank lookup is async; we PrintToChatAll inside the callback.
    DataPack dp = new DataPack();
    dp.WriteCell(GetClientUserId(client));

    char sql[512];
    FormatEx(sql, sizeof sql,
        "SELECT 1 + (SELECT COUNT(*) FROM v_player_totals t2 "
        ... "             WHERE t2.points > t1.points) AS rank, "
        ... "       t1.points "
        ... "FROM v_player_totals t1 WHERE t1.player_id = %d",
        g_Clients[client].playerId);
    g_DB.Query(OnAnnounceRankLookup, sql, dp);
}

static void OnAnnounceRankLookup(Database db, DBResultSet rs, const char[] error, DataPack dp)
{
    dp.Reset();
    int uid = dp.ReadCell();
    delete dp;
    if (rs == null || !rs.FetchRow()) return;
    int client = GetClientOfUserId(uid);
    if (client == 0) return;
    int rank   = rs.FetchInt(0);
    int points = rs.FetchInt(1);
    PrintToChatAll("\x04[bizzymod-stats]\x01 %N joined the game! (Rank: %d, Points: %d)",
        client, rank, points);
}
