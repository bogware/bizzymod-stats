/**
 * versus.sp — match/map/round tracking for Versus / Realism Versus / Scavenge.
 *
 * Terminology (this is where people trip up):
 *   match  = one whole campaign (all chapters). Rarely finishes — players leave.
 *   map    = one CHAPTER, i.e. BOTH halves (you play Survivor once and Infected
 *            once). This is what a player colloquially calls "a round of versus",
 *            and it reliably completes because you must finish it to progress.
 *   round  = one HALF (one team on Survivors). Two per map.
 *
 * Because whole matches almost never finish, per-player versus stats are rolled
 * up PER MAP (per chapter) at chapter close — not at match close. A completed
 * chapter credits everyone who played it immediately, even if the match is later
 * abandoned. The chapter rollup runs inside the round-2 transaction so it is
 * atomic and cannot race the round-2 player_round_stats inserts.
 *
 * Round detection: the engine's `round_start` fires once per half. We count
 * halves within a chapter (g_MapRoundOrdinal, reset at OpenMatchMap) rather than
 * trusting versus_round_start's `is_secondary_round`, which is unreliable on this
 * build (it stays false, so every half tried to insert as round 1 and hit the
 * uq_round_idx unique key). Idempotency guards make us robust to round_start
 * firing more than twice.
 *
 * Two parallel counter banks:
 *   g_Clients[client].*       — session-scoped (drives player_stats), owned by session.sp
 *   g_RoundClients[client].*  — round(half)-scoped (drives player_round_stats), owned here
 * Bizzy_Score() mirrors into both. Round counters reset at OpenRound.
 */

// -----------------------------------------------------------------------------
// State
// -----------------------------------------------------------------------------

enum struct RoundClient
{
    int  points;
    int  kills;
    int  deaths;
    int  incaps;
    int  damageDealt;
    int  damageTaken;
    int  damageFriendly;
    int  awards;
    int  startEpoch;
    int  side;  // last seen GetClientTeam (2=surv, 3=inf, 0=spec)
}

RoundClient g_RoundClients[MAXPLAYERS + 1];
char        g_PlayerTeam[MAXPLAYERS + 1]; // '\0', 'A', or 'B'

int  g_MatchId             = 0;
int  g_MatchMapId          = 0;
int  g_MatchMapMapId       = 0;   // map_id of the currently-open chapter (re-entry guard)
int  g_MatchMapOrdinal     = 0;   // chapter number within the match (1..N)
int  g_MapRoundOrdinal     = 0;   // halves opened on the CURRENT chapter (0,1,2)
int  g_RoundId             = 0;
int  g_RoundIndex          = 0;   // 0=between, 1 or 2 during a half
char g_SurvivorTeam        = '\0'; // letter of whoever currently plays survivors
char g_MatchCampaign[64]   = "";

bool g_VersusActive        = false; // current gamemode is a versus-like mode
int  g_RoundStartEpoch     = 0;
int  g_TeamScoreA          = 0; // cumulative on current match
int  g_TeamScoreB          = 0;
int  g_MatchMapPluginA     = 0; // plugin Survivor points on current chapter (drives the winner)
int  g_MatchMapPluginB     = 0;

bool g_TankAppearedRound   = false;
bool g_WitchAppearedRound  = false;
bool g_FirstBloodFired     = false;
bool g_FirstDownFired      = false;

// -----------------------------------------------------------------------------
// Init
// -----------------------------------------------------------------------------

void Bizzy_OnVersusInit()
{
    // Half boundaries come from the ENGINE round events (fire once per half),
    // not versus_round_start (whose is_secondary_round is unreliable here). We
    // guard every handler with g_VersusActive so coop round_starts are ignored.
    HookEventEx("round_start",           Event_VRoundStart, EventHookMode_PostNoCopy);
    HookEventEx("round_end",             Event_VRoundEnd,   EventHookMode_Post);
    HookEventEx("versus_match_finished", Event_VMatchFinished, EventHookMode_PostNoCopy);
    HookEventEx("scavenge_match_finished", Event_VMatchFinished, EventHookMode_PostNoCopy);
    HookEventEx("player_team",           Event_VPlayerTeam, EventHookMode_Post);
    HookEventEx("tank_spawn",            Event_VTankSpawn,  EventHookMode_PostNoCopy);
    HookEventEx("witch_spawn",           Event_VWitchSpawn, EventHookMode_PostNoCopy);
    HookEventEx("map_transition",        Event_VMapTransition, EventHookMode_PostNoCopy);

    // Clear any open matches from a previous load on THIS server — we can't
    // reliably resume mid-match across plugin restarts.
    AbandonStaleMatchesForServer();
}

// On every map start, decide whether to open/continue/close a match.
// Called by session.sp's Bizzy_OnMapStart() chain.
stock void Bizzy_Versus_OnMapStart()
{
    g_VersusActive = (g_CurrentMode == GameMode_Versus
                   || g_CurrentMode == GameMode_RealismVersus
                   || g_CurrentMode == GameMode_Scavenge);

    if (!g_VersusActive)
    {
        if (g_MatchId != 0) CloseMatch("mode_change", 'X');
        return;
    }

    char campaign[64];
    DeriveCampaignCode(g_CurrentMap, campaign, sizeof campaign);

    if (g_MatchId == 0)
    {
        // OpenMatch inserts the matches row ASYNC; the first chapter is opened
        // from OnMatchInserted once g_MatchId is set. Do NOT call OpenMatchMap()
        // inline here — g_MatchId is still 0 this frame and the chapter (and its
        // rounds + rollup) would be silently dropped.
        OpenMatch(campaign);
    }
    else if (!StrEqual(campaign, g_MatchCampaign))
    {
        // Different campaign: previous match is implicitly over. Winner decided
        // (0 = auto) after CloseMatch flushes the last chapter's scores.
        CloseMatch("campaign_change", 0);
        OpenMatch(campaign);   // OnMatchInserted opens the first chapter
    }
    else
    {
        // Continuing the same match — g_MatchId is already set, safe to open now.
        OpenMatchMap();
    }
}

// -----------------------------------------------------------------------------
// Match lifecycle
// -----------------------------------------------------------------------------

static void OpenMatch(const char[] campaign)
{
    if (g_DB == null || g_ServerId == 0) return;

    strcopy(g_MatchCampaign, sizeof g_MatchCampaign, campaign);
    g_MatchMapOrdinal = 0;
    g_TeamScoreA = 0;
    g_TeamScoreB = 0;
    g_SurvivorTeam = '\0';
    for (int i = 1; i <= MaxClients; i++) g_PlayerTeam[i] = '\0';

    char escCamp[160];
    Bizzy_DB_Escape(campaign, escCamp, sizeof escCamp);

    char sql[512];
    FormatEx(sql, sizeof sql,
        "INSERT INTO matches (server_id, gamemode_id, difficulty_id, campaign, started_at) "
        ... "VALUES (%d, %d, %d, NULLIF('%s',''), NOW())",
        g_ServerId, view_as<int>(g_CurrentMode), view_as<int>(g_CurrentDifficulty),
        escCamp);
    g_DB.Query(OnMatchInserted, sql);
}

static void OnMatchInserted(Database db, DBResultSet rs, const char[] error, any data)
{
    if (rs == null) { LogError("[bizzymod-stats] match insert: %s", error); return; }
    g_MatchId = rs.InsertId;

    // Seed both team rows so foreign keys in match_team_players line up.
    Transaction t = Bizzy_DB_BeginTxn();
    char sql[256];
    FormatEx(sql, sizeof sql,
        "INSERT INTO match_teams (match_id, team_letter) VALUES (%d, 'A')", g_MatchId);
    t.AddQuery(sql);
    FormatEx(sql, sizeof sql,
        "INSERT INTO match_teams (match_id, team_letter) VALUES (%d, 'B')", g_MatchId);
    t.AddQuery(sql);
    Bizzy_DB_RunTxn(t);

    LogMessage("[bizzymod-stats] match opened: id=%d campaign=%s", g_MatchId, g_MatchCampaign);

    // g_MatchId is now set — open the first chapter here (NOT inline after
    // OpenMatch, where g_MatchId was still 0).
    OpenMatchMap();
}

static void CloseMatch(const char[] reason, int winnerChar)
{
    if (g_MatchId == 0) return;

    // Commit a still-open half (e.g. versus_match_finished arriving before the
    // final round_end), then flush the still-open chapter, BEFORE deciding the
    // winner / writing — so the final chapter's rounds, per-player rollup and
    // scores are all captured and folded into the cumulative team score.
    if (g_RoundIndex != 0)
        CloseRound(0, 0, 0);
    if (g_MatchMapId != 0)
        FlushOpenMap();

    // winnerChar == 0 means "decide from the (now-final) cumulative scores".
    int wn = (winnerChar == 0) ? DecideMatchWinner() : winnerChar;
    char winnerEnum[16];
    if      (wn == 'A')  strcopy(winnerEnum, sizeof winnerEnum, "A");
    else if (wn == 'B')  strcopy(winnerEnum, sizeof winnerEnum, "B");
    else if (wn == 'D')  strcopy(winnerEnum, sizeof winnerEnum, "draw");
    else                 strcopy(winnerEnum, sizeof winnerEnum, "abandoned");

    char escReason[96];
    Bizzy_DB_Escape(reason, escReason, sizeof escReason);

    // team_*_score columns are UNSIGNED; plugin-derived cumulative scores can go
    // negative (friendly-fire penalties), so clamp for storage.
    int teamA = (g_TeamScoreA < 0) ? 0 : g_TeamScoreA;
    int teamB = (g_TeamScoreB < 0) ? 0 : g_TeamScoreB;

    Transaction t = Bizzy_DB_BeginTxn();
    char sql[512];

    FormatEx(sql, sizeof sql,
        "UPDATE matches SET ended_at=NOW(), team_a_score=%d, team_b_score=%d, "
        ... "winner='%s', end_reason='%s' WHERE id=%d",
        teamA, teamB, winnerEnum, escReason, g_MatchId);
    t.AddQuery(sql);

    FormatEx(sql, sizeof sql,
        "UPDATE match_teams SET final_score=%d WHERE match_id=%d AND team_letter='A'",
        teamA, g_MatchId);
    t.AddQuery(sql);
    FormatEx(sql, sizeof sql,
        "UPDATE match_teams SET final_score=%d WHERE match_id=%d AND team_letter='B'",
        teamB, g_MatchId);
    t.AddQuery(sql);

    Bizzy_DB_RunTxn(t);

    // Match-LEVEL rollup only: matches_played/won/lost/drawn/abandoned. The
    // maps/rounds/score counters AND the win/loss STREAKS are credited per
    // chapter in AppendPlayerVersusRollupForMap (so a "win streak" counts
    // consecutive chapters won), and are NOT touched here — avoids double count.
    UpdatePlayerVersusMatchTotals(wn);

    LogMessage("[bizzymod-stats] match closed: id=%d winner=%s reason=%s (A=%d B=%d)",
        g_MatchId, winnerEnum, reason, teamA, teamB);

    g_MatchId = 0;
    g_MatchMapId = 0;
    g_MatchMapOrdinal = 0;
    g_MapRoundOrdinal = 0;
    g_RoundId = 0;
    g_RoundIndex = 0;
    g_MatchCampaign[0] = '\0';
}

static int DecideMatchWinner()
{
    if (g_TeamScoreA > g_TeamScoreB) return 'A';
    if (g_TeamScoreB > g_TeamScoreA) return 'B';
    return 'D';
}

// -----------------------------------------------------------------------------
// Map (chapter) lifecycle within a match
// -----------------------------------------------------------------------------

static void OpenMatchMap()
{
    if (g_MatchId == 0 || g_CurrentMapId == 0) return;

    // Re-entry guard: if OnMapStart fires again for the SAME chapter that is
    // already open and not yet complete (an engine re-exec between halves would
    // do this), do NOT flush + reopen — that would split one chapter into two.
    if (g_MatchMapId != 0 && g_MatchMapMapId == g_CurrentMapId && g_MapRoundOrdinal < 2)
        return;

    // A DIFFERENT chapter is still open (previous chapter never saw its round 2
    // close) — flush it so we don't dangle an incomplete chapter.
    if (g_MatchMapId != 0)
        FlushOpenMap();

    g_MatchMapOrdinal++;
    g_MapRoundOrdinal = 0;
    g_MatchMapMapId = g_CurrentMapId;
    g_MatchMapPluginA = 0;
    g_MatchMapPluginB = 0;

    char sql[256];
    FormatEx(sql, sizeof sql,
        "INSERT INTO match_maps (match_id, map_id, ordinal, started_at) "
        ... "VALUES (%d, %d, %d, NOW())",
        g_MatchId, g_CurrentMapId, g_MatchMapOrdinal);
    g_DB.Query(OnMatchMapInserted, sql);
}

static void OnMatchMapInserted(Database db, DBResultSet rs, const char[] error, any data)
{
    if (rs == null) { LogError("[bizzymod-stats] match_map insert: %s", error); return; }
    g_MatchMapId = rs.InsertId;
}

// Decide the chapter winner from the accumulated per-team survivor scores.
// Engine (distance) score is authoritative when available; if both are 0 (the
// netprop isn't exposed on this build), fall back to plugin survivor points so a
// completed chapter still resolves a winner instead of a spurious draw.
static int DecideMapWinner()
{
    // The engine distance/campaign netprop is not reliably exposed on this build
    // (it reads 0), so decide the chapter winner from plugin Survivor points —
    // the side that performed better across its two Survivor halves. An engine-
    // distance-accurate winner is a future refinement (needs a reliable score
    // source + live-versus validation).
    if (g_MatchMapPluginA != g_MatchMapPluginB)
        return (g_MatchMapPluginA > g_MatchMapPluginB) ? 'A' : 'B';
    return 'D';
}

// Append the chapter close + per-player versus rollup to an OPEN transaction.
// Called from CloseRound when round 2 ends, so it shares the round-2 txn and the
// rollup SELECT sees this chapter's just-inserted round-2 player_round_stats.
static void AppendMapCloseAndRollup(Transaction t)
{
    if (g_MatchMapId == 0) return;

    int wn = DecideMapWinner();
    char winnerEnum[16];
    if      (wn == 'A') strcopy(winnerEnum, sizeof winnerEnum, "A");
    else if (wn == 'B') strcopy(winnerEnum, sizeof winnerEnum, "B");
    else                strcopy(winnerEnum, sizeof winnerEnum, "draw");

    // Chapter scores come from plugin Survivor points (engine distance isn't
    // available here). The cumulative match score keeps the signed values for
    // winner decisions; the UNSIGNED team_*_score columns get a clamped copy.
    g_TeamScoreA += g_MatchMapPluginA;
    g_TeamScoreB += g_MatchMapPluginB;
    int scoreA = (g_MatchMapPluginA < 0) ? 0 : g_MatchMapPluginA;
    int scoreB = (g_MatchMapPluginB < 0) ? 0 : g_MatchMapPluginB;

    char sql[384];
    FormatEx(sql, sizeof sql,
        "UPDATE match_maps SET ended_at=NOW(), team_a_score=%d, team_b_score=%d, winner='%s' "
        ... "WHERE id=%d",
        scoreA, scoreB, winnerEnum, g_MatchMapId);
    t.AddQuery(sql);

    if (wn == 'A')
    {
        FormatEx(sql, sizeof sql,
            "UPDATE match_teams SET maps_won=maps_won+1 WHERE match_id=%d AND team_letter='A'", g_MatchId);
        t.AddQuery(sql);
        FormatEx(sql, sizeof sql,
            "UPDATE match_teams SET maps_lost=maps_lost+1 WHERE match_id=%d AND team_letter='B'", g_MatchId);
        t.AddQuery(sql);
    }
    else if (wn == 'B')
    {
        FormatEx(sql, sizeof sql,
            "UPDATE match_teams SET maps_won=maps_won+1 WHERE match_id=%d AND team_letter='B'", g_MatchId);
        t.AddQuery(sql);
        FormatEx(sql, sizeof sql,
            "UPDATE match_teams SET maps_lost=maps_lost+1 WHERE match_id=%d AND team_letter='A'", g_MatchId);
        t.AddQuery(sql);
    }

    FormatEx(sql, sizeof sql,
        "UPDATE matches SET maps_played=maps_played+1 WHERE id=%d", g_MatchId);
    t.AddQuery(sql);

    AppendPlayerVersusRollupForMap(t, g_MatchMapId, wn);
}

// Roll each player's completed-chapter contribution into player_versus_stats.
// One UPSERT per team letter, keyed on (player_id, gamemode_id). Reads this
// chapter's two halves from player_round_stats (visible in the shared txn).
static void AppendPlayerVersusRollupForMap(Transaction t, int mapId, int winnerChar)
{
    int gm = view_as<int>(g_CurrentMode);

    for (int letter = 0; letter < 2; letter++)
    {
        char L = (letter == 0) ? 'A' : 'B';
        int wonInc  = (winnerChar == L) ? 1 : 0;
        int lostInc = (winnerChar != L && (winnerChar == 'A' || winnerChar == 'B')) ? 1 : 0;

        char sql[2048];
        FormatEx(sql, sizeof sql,
            "INSERT INTO player_versus_stats "
            ... "(player_id, gamemode_id, maps_won, maps_lost, rounds_played, rounds_won, rounds_lost, "
            ... " rounds_as_surv, rounds_as_inf, total_round_score_surv, total_round_score_inf, "
            ... " current_win_streak, longest_win_streak, current_loss_streak, longest_loss_streak, last_match_at) "
            ... "SELECT prs.player_id, %d, %d, %d, COUNT(*), "
            // rounds_won/rounds_lost: a versus HALF has no individual winner (the
            // chapter is decided by comparing the two halves), so these stay 0.
            // The player's win/loss record is maps_won/maps_lost (one per chapter).
            ... "       0, 0, "
            ... "       SUM(prs.side=2), SUM(prs.side=3), "
            ... "       SUM(IF(prs.side=2, prs.points, 0)), SUM(IF(prs.side=3, prs.points, 0)), "
            ... "       %d, %d, %d, %d, NOW() "
            ... "FROM player_round_stats prs "
            ... "JOIN match_rounds mr ON mr.id = prs.match_round_id "
            ... "WHERE mr.match_map_id=%d AND prs.team_letter='%c' "
            ... "GROUP BY prs.player_id "
            ... "ON DUPLICATE KEY UPDATE "
            ... " maps_won               = maps_won               + VALUES(maps_won), "
            ... " maps_lost              = maps_lost              + VALUES(maps_lost), "
            ... " rounds_played          = rounds_played          + VALUES(rounds_played), "
            ... " rounds_won             = rounds_won             + VALUES(rounds_won), "
            ... " rounds_lost            = rounds_lost            + VALUES(rounds_lost), "
            ... " rounds_as_surv         = rounds_as_surv         + VALUES(rounds_as_surv), "
            ... " rounds_as_inf          = rounds_as_inf          + VALUES(rounds_as_inf), "
            ... " total_round_score_surv = total_round_score_surv + VALUES(total_round_score_surv), "
            ... " total_round_score_inf  = total_round_score_inf  + VALUES(total_round_score_inf), "
            ... " current_win_streak  = IF(%d=1, current_win_streak + 1, IF(%d=1, 0, current_win_streak)), "
            ... " longest_win_streak  = GREATEST(longest_win_streak, current_win_streak), "
            ... " current_loss_streak = IF(%d=1, current_loss_streak + 1, IF(%d=1, 0, current_loss_streak)), "
            ... " longest_loss_streak = GREATEST(longest_loss_streak, current_loss_streak), "
            ... " last_match_at = NOW()",
            gm, wonInc, lostInc,                // gamemode_id, maps_won, maps_lost
            wonInc, wonInc, lostInc, lostInc,   // initial streak values on INSERT
            mapId, L,                           // WHERE match_map_id, team_letter
            wonInc, lostInc,                    // current_win_streak update
            lostInc, wonInc);                   // current_loss_streak update
        t.AddQuery(sql);
    }
}

// Close an open chapter OUTSIDE the round-2 path (abandon / map transition with a
// dangling chapter). Runs its own transaction. A partial chapter (only round 1
// played) still resolves a winner from what we have and credits its players.
static void FlushOpenMap()
{
    if (g_MatchMapId == 0) return;
    Transaction t = Bizzy_DB_BeginTxn();
    AppendMapCloseAndRollup(t);
    Bizzy_DB_RunTxn(t);
    g_MatchMapId = 0;
    g_MapRoundOrdinal = 0;
}

// -----------------------------------------------------------------------------
// Round (half) lifecycle
// -----------------------------------------------------------------------------

static void Event_VRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_VersusActive || g_MatchId == 0 || g_MatchMapId == 0) return;

    // Idempotent: ignore round_start re-fires while a half is already open, and
    // ignore anything past the second half of a chapter.
    if (g_RoundIndex != 0) return;
    if (g_MapRoundOrdinal >= 2) return;

    g_MapRoundOrdinal++;
    OpenRound(g_MapRoundOrdinal);
}

static void OpenRound(int roundIndex)
{
    g_RoundIndex      = roundIndex;
    g_RoundStartEpoch = Bizzy_NowEpoch();
    g_TankAppearedRound = false;
    g_WitchAppearedRound = false;
    g_FirstBloodFired = false;
    g_FirstDownFired = false;

    // Reset round-scoped counters
    for (int i = 1; i <= MaxClients; i++)
    {
        g_RoundClients[i].points = 0;
        g_RoundClients[i].kills = 0;
        g_RoundClients[i].deaths = 0;
        g_RoundClients[i].incaps = 0;
        g_RoundClients[i].damageDealt = 0;
        g_RoundClients[i].damageTaken = 0;
        g_RoundClients[i].damageFriendly = 0;
        g_RoundClients[i].awards = 0;
        g_RoundClients[i].startEpoch = g_RoundStartEpoch;
        g_RoundClients[i].side = (IsClientInGame(i) && !IsFakeClient(i))
            ? GetClientTeam(i) : 0;
    }

    // Decide which persistent letter plays Survivors this half. Team letters
    // (A/B) are fixed for the whole match; only the SIDE flips each half. Rather
    // than flip-count (fragile across chapters), read the survivor letter from
    // whoever is actually on the engine Survivor team right now — the sides are
    // already set for this half when round_start fires.
    bool anyLettered = false;
    for (int i = 1; i <= MaxClients; i++)
        if (g_PlayerTeam[i] != '\0') { anyLettered = true; break; }

    if (!anyLettered)
    {
        // Fresh match: seed letters from current sides, Survivors become A.
        g_SurvivorTeam = 'A';
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!Bizzy_IsValidPlayer(i)) continue;
            int tm = GetClientTeam(i);
            if      (tm == TEAM_SURVIVORS) AssignTeamLetter(i, 'A');
            else if (tm == TEAM_INFECTED)  AssignTeamLetter(i, 'B');
        }
    }
    else
    {
        char survLetter = '\0';
        for (int i = 1; i <= MaxClients; i++)
        {
            if (g_PlayerTeam[i] == '\0' || !IsClientInGame(i)) continue;
            if (GetClientTeam(i) == TEAM_SURVIVORS) { survLetter = g_PlayerTeam[i]; break; }
        }
        if (survLetter == '\0')
        {
            if (g_SurvivorTeam != '\0') survLetter = g_SurvivorTeam;
            else                        survLetter = 'A';
        }
        g_SurvivorTeam = survLetter;
        AssignLettersFromCurrentSides();
    }

    if (g_MatchMapId == 0) { LogError("[bizzymod-stats] OpenRound with no match_map_id"); return; }

    char sql[384];
    FormatEx(sql, sizeof sql,
        "INSERT INTO match_rounds (match_id, match_map_id, round_index, survivor_team, started_at) "
        ... "VALUES (%d, %d, %d, '%c', NOW())",
        g_MatchId, g_MatchMapId, roundIndex, g_SurvivorTeam);
    g_DB.Query(OnRoundInserted, sql);
}

// Late/unlettered players: give them a letter from their current engine side,
// consistent with which letter is on Survivors this half.
static void AssignLettersFromCurrentSides()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!Bizzy_IsValidPlayer(i)) continue;
        if (g_PlayerTeam[i] != '\0') continue;
        int t = GetClientTeam(i);
        if (t == TEAM_SURVIVORS)     AssignTeamLetter(i, g_SurvivorTeam);
        else if (t == TEAM_INFECTED) AssignTeamLetter(i, (g_SurvivorTeam == 'A') ? 'B' : 'A');
    }
}

static void OnRoundInserted(Database db, DBResultSet rs, const char[] error, any data)
{
    if (rs == null) { LogError("[bizzymod-stats] round insert: %s", error); return; }
    g_RoundId = rs.InsertId;
}

static void Event_VRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_VersusActive || g_MatchId == 0 || g_RoundIndex == 0) return;

    int reason = event.GetInt("reason", 0);
    int winner = event.GetInt("winner", 0);
    int engineScore = ReadEngineCampaignScoreForSurvTeam();

    CloseRound(reason, winner, engineScore);
}

static void CloseRound(int reason, int winnerTeam, int engineScore)
{
    if (g_RoundId == 0) return;
    int duration = Bizzy_NowEpoch() - g_RoundStartEpoch;
    if (duration < 0) duration = 0;

    // Sum plugin scores by side and count survivors still standing.
    int sumSurv = 0, sumInf = 0, survLeft = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_PlayerTeam[i] == '\0') continue;
        int side = g_RoundClients[i].side;
        if (side == TEAM_SURVIVORS) sumSurv += g_RoundClients[i].points;
        else if (side == TEAM_INFECTED) sumInf += g_RoundClients[i].points;
        if (side == TEAM_SURVIVORS && IsClientInGame(i) && IsPlayerAlive(i)) survLeft++;
    }

    char endReason[48];
    DescribeRoundEndReason(reason, winnerTeam, endReason, sizeof endReason);
    char escReason[100];
    Bizzy_DB_Escape(endReason, escReason, sizeof escReason);

    Transaction t = Bizzy_DB_BeginTxn();
    char sql[640];

    FormatEx(sql, sizeof sql,
        "UPDATE match_rounds SET ended_at=NOW(), duration_s=%d, engine_score=%d, "
        ... "plugin_score_surv=%d, plugin_score_inf=%d, survivors_left=%d, "
        ... "tank_appeared=%d, witch_appeared=%d, end_reason='%s' WHERE id=%d",
        duration, engineScore, sumSurv, sumInf, survLeft,
        g_TankAppearedRound ? 1 : 0, g_WitchAppearedRound ? 1 : 0,
        escReason, g_RoundId);
    t.AddQuery(sql);

    // Per-player half breakdown.
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_PlayerTeam[i] == '\0') continue;
        if (g_Clients[i].playerId == 0) continue;
        int side = g_RoundClients[i].side;
        if (side != TEAM_SURVIVORS && side != TEAM_INFECTED) continue;

        FormatEx(sql, sizeof sql,
            "INSERT INTO player_round_stats "
            ... "(match_round_id, player_id, team_letter, side, points, kills, deaths, incaps, "
            ... " damage_dealt, damage_taken, damage_friendly, time_in_round_s, awards_count) "
            ... "VALUES (%d, %d, '%c', %d, %d, %d, %d, %d, %d, %d, %d, %d, %d) "
            ... "ON DUPLICATE KEY UPDATE "
            ... " points=VALUES(points), kills=VALUES(kills), deaths=VALUES(deaths), "
            ... " incaps=VALUES(incaps), damage_dealt=VALUES(damage_dealt), "
            ... " damage_taken=VALUES(damage_taken), damage_friendly=VALUES(damage_friendly), "
            ... " time_in_round_s=VALUES(time_in_round_s), awards_count=VALUES(awards_count)",
            g_RoundId, g_Clients[i].playerId, g_PlayerTeam[i], side,
            g_RoundClients[i].points, g_RoundClients[i].kills,
            g_RoundClients[i].deaths, g_RoundClients[i].incaps,
            g_RoundClients[i].damageDealt, g_RoundClients[i].damageTaken,
            g_RoundClients[i].damageFriendly, duration,
            g_RoundClients[i].awards);
        t.AddQuery(sql);
    }

    FormatEx(sql, sizeof sql,
        "UPDATE matches SET rounds_played=rounds_played+1 WHERE id=%d", g_MatchId);
    t.AddQuery(sql);

    // Accumulate this half's Survivor plugin points onto the chapter totals.
    // (engine_score is stored per-round for reference but is not used to score
    // chapters — see DecideMapWinner.)
    if (g_SurvivorTeam == 'A') g_MatchMapPluginA += sumSurv;
    else                       g_MatchMapPluginB += sumSurv;

    int closedIndex = g_RoundIndex;

    // Round 2 just ended → the chapter is complete. Close it and roll up the
    // per-player versus stats IN THIS SAME transaction, so the rollup SELECT sees
    // the round-2 player_round_stats we just queued above.
    if (closedIndex == 2)
        AppendMapCloseAndRollup(t);

    Bizzy_DB_RunTxn(t);

    g_RoundId = 0;
    g_RoundIndex = 0;
    if (closedIndex == 2)
    {
        g_MatchMapId = 0;
        g_MapRoundOrdinal = 0;
    }
}

static void Event_VMatchFinished(Event event, const char[] name, bool dontBroadcast)
{
    if (g_MatchId == 0) return;
    CloseMatch("finale", 0);   // 0 = decide winner after flushing the final chapter
}

static void Event_VMapTransition(Event event, const char[] name, bool dontBroadcast)
{
    // Safety net: close a dangling half, then flush the chapter if it is still
    // open (e.g. round 2 didn't fire a clean round_end before the transition).
    if (g_RoundIndex != 0)
        CloseRound(0, 0, 0);
    if (g_MatchMapId != 0)
        FlushOpenMap();
}

// -----------------------------------------------------------------------------
// Per-player events
// -----------------------------------------------------------------------------

static void Event_VPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!Bizzy_IsValidPlayer(client) || g_MatchId == 0) return;

    int newTeam = event.GetInt("team");
    g_RoundClients[client].side = newTeam;

    // Engine flips happen between round_end and round_start; during those windows
    // g_RoundIndex is 0, so we don't change the letter. Voluntary jointeam during
    // an active half flips the letter.
    if (g_RoundIndex == 0) return;
    if (newTeam != TEAM_SURVIVORS && newTeam != TEAM_INFECTED) return;

    char expected;
    if (newTeam == TEAM_SURVIVORS) expected = g_SurvivorTeam;
    else                           expected = (g_SurvivorTeam == 'A') ? 'B' : 'A';

    if (g_PlayerTeam[client] != '\0' && g_PlayerTeam[client] != expected)
    {
        CloseMembership(client, g_PlayerTeam[client]);
        OpenMembership(client, expected, g_RoundIndex);
        g_PlayerTeam[client] = expected;
    }
    else if (g_PlayerTeam[client] == '\0')
    {
        AssignTeamLetter(client, expected);
    }
}

static void Event_VTankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (g_RoundIndex != 0) g_TankAppearedRound = true;
}

static void Event_VWitchSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (g_RoundIndex != 0) g_WitchAppearedRound = true;
}

// -----------------------------------------------------------------------------
// Team membership rows
// -----------------------------------------------------------------------------

static void AssignTeamLetter(int client, int letterChar)
{
    if (g_Clients[client].playerId == 0) return;
    g_PlayerTeam[client] = letterChar;
    OpenMembership(client, letterChar, g_RoundIndex);
}

static void OpenMembership(int client, int letterChar, int joinedRound)
{
    if (g_MatchId == 0 || g_Clients[client].playerId == 0) return;
    char sql[384];
    FormatEx(sql, sizeof sql,
        "INSERT INTO match_team_players "
        ... "(match_id, team_letter, player_id, joined_round, time_on_team_s) "
        ... "VALUES (%d, '%c', %d, %d, 0) "
        ... "ON DUPLICATE KEY UPDATE left_round=NULL",
        g_MatchId, letterChar, g_Clients[client].playerId, joinedRound);
    Bizzy_DB_Exec(sql);
}

static void CloseMembership(int client, int letterChar)
{
    if (g_MatchId == 0 || g_Clients[client].playerId == 0) return;
    char sql[384];
    FormatEx(sql, sizeof sql,
        "UPDATE match_team_players SET left_round=%d "
        ... "WHERE match_id=%d AND team_letter='%c' AND player_id=%d AND left_round IS NULL",
        g_RoundIndex, g_MatchId, letterChar, g_Clients[client].playerId);
    Bizzy_DB_Exec(sql);
}

// -----------------------------------------------------------------------------
// player_versus_stats: MATCH-level totals at match close (whole-campaign
// counters + streaks are NOT here — those are per-chapter). This only credits
// matches_played and the match win/loss/draw/abandon tally.
// -----------------------------------------------------------------------------

static void UpdatePlayerVersusMatchTotals(int winnerChar)
{
    if (g_MatchId == 0) return;

    char winLetter = (winnerChar == 'A' || winnerChar == 'B') ? winnerChar : 'X';
    bool isDraw    = (winnerChar == 'D');
    bool isAbandon = (winnerChar == 'X');
    int gm = view_as<int>(g_CurrentMode);

    for (int letter = 0; letter < 2; letter++)
    {
        char L = (letter == 0) ? 'A' : 'B';
        bool teamWon = (L == winLetter);

        int wonInc     = isAbandon ? 0 : (teamWon ? 1 : 0);
        int lostInc    = isAbandon ? 0 : (!teamWon && !isDraw ? 1 : 0);
        int drawInc    = isDraw ? 1 : 0;
        int abandonInc = isAbandon ? 1 : 0;

        char sql[1024];
        FormatEx(sql, sizeof sql,
            "INSERT INTO player_versus_stats "
            ... "(player_id, gamemode_id, matches_played, matches_won, matches_lost, "
            ... " matches_drawn, matches_abandoned, last_match_at) "
            ... "SELECT mtp.player_id, %d, 1, %d, %d, %d, %d, NOW() "
            ... "FROM match_team_players mtp "
            ... "WHERE mtp.match_id=%d AND mtp.team_letter='%c' "
            ... "GROUP BY mtp.player_id "
            ... "ON DUPLICATE KEY UPDATE "
            ... " matches_played    = matches_played + 1, "
            ... " matches_won       = matches_won + VALUES(matches_won), "
            ... " matches_lost      = matches_lost + VALUES(matches_lost), "
            ... " matches_drawn     = matches_drawn + VALUES(matches_drawn), "
            ... " matches_abandoned = matches_abandoned + VALUES(matches_abandoned), "
            ... " last_match_at = NOW()",
            gm, wonInc, lostInc, drawInc, abandonInc,
            g_MatchId, L);
        Bizzy_DB_Exec(sql);
    }
}

// -----------------------------------------------------------------------------
// External hooks (called from scoring.sp, events.sp, awards.sp)
// -----------------------------------------------------------------------------

stock void Bizzy_Versus_AccumScore(int client, int points)
{
    if (g_RoundIndex == 0) return;
    g_RoundClients[client].points += points;
}

stock void Bizzy_Versus_AccumKill(int client, bool isDeath = false)
{
    if (g_RoundIndex == 0) return;
    if (isDeath)
    {
        g_RoundClients[client].deaths++;
        if (!g_FirstDownFired && Bizzy_IsValidPlayer(client)
            && GetClientTeam(client) == TEAM_SURVIVORS)
        {
            g_FirstDownFired = true;
            g_Clients[client].firstDowns++;
            Bizzy_Awards_Fire(client, "first_down", 1);
        }
    }
    else
    {
        g_RoundClients[client].kills++;
        if (!g_FirstBloodFired && Bizzy_IsValidPlayer(client)
            && GetClientTeam(client) == TEAM_INFECTED)
        {
            g_FirstBloodFired = true;
            g_Clients[client].firstBloods++;
            Bizzy_Awards_Fire(client, "first_blood", 1);
        }
    }
}

stock void Bizzy_Versus_AccumDamage(int attacker, int victim, int damage, bool friendly)
{
    if (g_RoundIndex == 0) return;
    if (Bizzy_IsValidPlayer(attacker))
    {
        g_RoundClients[attacker].damageDealt += damage;
        if (friendly) g_RoundClients[attacker].damageFriendly += damage;
    }
    if (Bizzy_IsValidPlayer(victim))
        g_RoundClients[victim].damageTaken += damage;
}

stock void Bizzy_Versus_AccumIncap(int client)
{
    if (g_RoundIndex == 0) return;
    g_RoundClients[client].incaps++;
}

stock void Bizzy_Versus_AccumAward(int client)
{
    if (g_RoundIndex == 0) return;
    g_RoundClients[client].awards++;
}

stock bool Bizzy_Versus_MatchActive() { return g_MatchId != 0; }
stock int  Bizzy_Versus_GetRoundId()  { return g_RoundId; }
stock int  Bizzy_Versus_GetMatchId()  { return g_MatchId; }

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

// Engine Survivor scenario (distance) score. Disabled: the m_iCampaignScore
// netprop on terror_player_manager is a per-VERSUS-TEAM (not per-side) CUMULATIVE
// array, so a naive per-half read mis-attributes and double-adds it, and it reads
// 0 on this build anyway. Chapter winners come from plugin Survivor points
// instead (DecideMapWinner). Kept as a seam: wire a reliable per-half distance
// source here (e.g. L4D2Direct_GetVSCampaignScore delta) after live validation.
static int ReadEngineCampaignScoreForSurvTeam()
{
    return 0;
}

// "c2m3_coaster" → "c2"; for non-canonical names returns empty string.
static void DeriveCampaignCode(const char[] mapname, char[] out, int outlen)
{
    out[0] = '\0';
    if (mapname[0] != 'c' && mapname[0] != 'l') return;
    int n = strlen(mapname);
    int i = 0;
    while (i < n && i < outlen - 1)
    {
        char ch = mapname[i];
        if (ch >= '0' && ch <= '9') { out[i] = ch; i++; continue; }
        if (i == 0 && (ch == 'c' || ch == 'l')) { out[i] = ch; i++; continue; }
        if (ch == 'm' || ch == '_') break;
        out[i] = ch; i++;
    }
    out[i] = '\0';
    if (i < 2) out[0] = '\0';
}

static void DescribeRoundEndReason(int reason, int winnerTeam, char[] out, int outlen)
{
    char w[16];
    if (winnerTeam == TEAM_SURVIVORS)      strcopy(w, sizeof w, "surv_win");
    else if (winnerTeam == TEAM_INFECTED)  strcopy(w, sizeof w, "inf_win");
    else                                   strcopy(w, sizeof w, "draw");

    switch (reason)
    {
        case 0:  FormatEx(out, outlen, "%s/timeout",      w);
        case 1:  FormatEx(out, outlen, "%s/finale",       w);
        case 2:  FormatEx(out, outlen, "%s/wipe",         w);
        case 3:  FormatEx(out, outlen, "%s/saferoom",     w);
        case 4:  FormatEx(out, outlen, "%s/mission_lost", w);
        default: FormatEx(out, outlen, "%s/reason_%d",    w, reason);
    }
}

static void AbandonStaleMatchesForServer()
{
    if (g_DB == null || g_ServerId == 0)
    {
        // No server_id yet — queue for after identity resolves.
        CreateTimer(2.0, Timer_AbandonStale, _, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }
    char sql[256];
    FormatEx(sql, sizeof sql,
        "UPDATE matches SET ended_at=NOW(), winner='abandoned', end_reason='plugin_restart' "
        ... "WHERE server_id=%d AND ended_at IS NULL", g_ServerId);
    Bizzy_DB_Exec(sql);

    // Close any chapters that were left open by the interrupted match(es) so
    // they don't sit 'incomplete' forever.
    FormatEx(sql, sizeof sql,
        "UPDATE match_maps mm JOIN matches m ON m.id=mm.match_id "
        ... "SET mm.ended_at=NOW() "
        ... "WHERE m.server_id=%d AND mm.ended_at IS NULL", g_ServerId);
    Bizzy_DB_Exec(sql);
}

static Action Timer_AbandonStale(Handle timer)
{
    // AbandonStaleMatchesForServer re-arms its own 2s timer while g_ServerId is
    // still 0, so this one-shot timer just retries the call.
    AbandonStaleMatchesForServer();
    return Plugin_Stop;
}
