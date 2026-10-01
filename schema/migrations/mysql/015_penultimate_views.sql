-- 015_penultimate_views.sql
-- Penultimate / mini-game / tie outcome views for versus.
--
-- WHY: in competitive L4D2 the match is usually decided at the PENULTIMATE map —
-- the finale is chaotic (tank/luck), is frequently skipped (admin map-change), or
-- the game is simply "called" before it. Most of our matches end `abandoned`, so
-- the real decided outcome is lost. These views recover it from data we already
-- store (per-half survivor scores), with NO plugin change — they compute
-- retroactively over all history.
--
-- SCORING: cumulative survivor points, the same model the plugin uses for the
-- full-match winner (team A total survivor pts vs team B total survivor pts; higher
-- wins). plugin_score_surv on a round is the survivor team's points that half.
--
-- Pure views + one tiny reference table (finale_maps). Idempotent; safe to re-run.

-- ---------------------------------------------------------------------------
-- Finale identification. maps.is_finale / maps.chapter / maps.campaign are not
-- populated, so we pin the finale by map CODE. These are the official L4D2
-- campaign finales; add custom-campaign finale codes here as needed.
-- ---------------------------------------------------------------------------
-- code collation MUST match maps.code (utf8mb4_unicode_ci) or the JOINs below hit
-- "Illegal mix of collations". The ALTER keeps it correct if the table pre-existed.
CREATE TABLE IF NOT EXISTS finale_maps (
  code VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL PRIMARY KEY
) ENGINE=InnoDB;
ALTER TABLE finale_maps CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT IGNORE INTO finale_maps (code) VALUES
  ('c1m4_atrium'),            -- Dead Center
  ('c2m5_concert'),           -- Dark Carnival
  ('c3m4_plantation'),        -- Swamp Fever
  ('c4m5_milltown_escape'),   -- Hard Rain
  ('c5m5_bridge'),            -- The Parish
  ('c6m3_port'),              -- The Passing
  ('c7m3_port'),              -- The Sacrifice
  ('c8m5_rooftop'),           -- No Mercy
  ('c9m2_alleys'),            -- Crash Course
  ('c10m5_houseboat'),        -- Death Toll
  ('c11m5_runway'),           -- Dead Air
  ('c12m5_cornfield'),        -- Blood Harvest
  ('c13m4_cutthroatcreek'),   -- Cold Stream
  ('c14m2_lighthouse');       -- The Last Stand

-- ---------------------------------------------------------------------------
-- Helper: did a match reach its finale? (a match_map exists on a finale code)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_match_reached_finale AS
SELECT mm.match_id,
       MAX(fm.code IS NOT NULL) AS reached_finale
FROM match_maps mm
JOIN maps m ON m.id = mm.map_id
LEFT JOIN finale_maps fm ON fm.code = m.code
GROUP BY mm.match_id;

-- ---------------------------------------------------------------------------
-- Helper: cumulative SURVIVOR points per team over NON-FINALE maps only.
-- For a finale-reaching match this is the standing going INTO the finale.
-- For a non-finale match (no map is a finale) this sums ALL its maps.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_match_prefinale_scores AS
SELECT r.match_id,
       COALESCE(SUM(CASE WHEN r.survivor_team = 'A' THEN r.plugin_score_surv END), 0) AS a_pts,
       COALESCE(SUM(CASE WHEN r.survivor_team = 'B' THEN r.plugin_score_surv END), 0) AS b_pts,
       SUM(r.survivor_team = 'A') AS a_halves,
       SUM(r.survivor_team = 'B') AS b_halves
FROM match_rounds r
JOIN match_maps mm ON r.match_map_id = mm.id
JOIN maps m ON m.id = mm.map_id
LEFT JOIN finale_maps fm ON fm.code = m.code
WHERE fm.code IS NULL                    -- exclude the finale map
GROUP BY r.match_id;

-- ---------------------------------------------------------------------------
-- MATCH-LEVEL: PENULTIMATE winner (standing before the finale), ONLY for matches
-- that actually reached the finale. Includes whether the finale flipped the
-- result vs the real full-match winner.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_match_penultimate AS
SELECT ma.id            AS match_id,
       ma.campaign,
       ma.server_id,
       ma.gamemode_id,
       ma.started_at,
       s.a_pts,
       s.b_pts,
       (s.a_pts - s.b_pts) AS margin,
       CASE WHEN s.a_pts > s.b_pts THEN 'A'
            WHEN s.b_pts > s.a_pts THEN 'B'
            ELSE 'draw' END               AS penultimate_winner,
       ma.winner                          AS final_winner,
       (ma.winner IN ('A','B')
        AND ma.winner <> CASE WHEN s.a_pts > s.b_pts THEN 'A'
                              WHEN s.b_pts > s.a_pts THEN 'B'
                              ELSE 'draw' END) AS finale_flipped
FROM matches ma
JOIN v_match_reached_finale rf ON rf.match_id = ma.id AND rf.reached_finale = 1
JOIN v_match_prefinale_scores s ON s.match_id = ma.id
WHERE s.a_halves >= 1 AND s.b_halves >= 1;   -- both teams played a pre-finale survivor half

-- ---------------------------------------------------------------------------
-- MATCH-LEVEL: MINI-GAME winner — matches that did NOT reach the finale but where
-- both teams played at least one survivor half (so a fair decided outcome exists).
-- Rescues a result from otherwise-'abandoned' matches.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_match_minigame AS
SELECT ma.id            AS match_id,
       ma.campaign,
       ma.server_id,
       ma.gamemode_id,
       ma.started_at,
       s.a_pts,
       s.b_pts,
       (s.a_pts - s.b_pts)       AS margin,
       (s.a_halves + s.b_halves) AS halves_played,
       CASE WHEN s.a_pts > s.b_pts THEN 'A'
            WHEN s.b_pts > s.a_pts THEN 'B'
            ELSE 'draw' END       AS minigame_winner,
       ma.end_reason
FROM matches ma
JOIN v_match_reached_finale rf ON rf.match_id = ma.id AND rf.reached_finale = 0
JOIN v_match_prefinale_scores s ON s.match_id = ma.id
WHERE s.a_halves >= 1 AND s.b_halves >= 1;

-- ---------------------------------------------------------------------------
-- PER-PLAYER: penultimate W/L/draw + win-rate (decided penultimate matches only).
-- A player wins if their team_letter == the match's penultimate_winner.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_player_penultimate AS
SELECT mtp.player_id,
       COUNT(*)                                                      AS penult_matches,
       SUM(mtp.team_letter = p.penultimate_winner)                   AS penult_wins,
       SUM(p.penultimate_winner IN ('A','B')
           AND mtp.team_letter <> p.penultimate_winner)              AS penult_losses,
       SUM(p.penultimate_winner = 'draw')                           AS penult_draws,
       ROUND(100 * SUM(mtp.team_letter = p.penultimate_winner)
             / NULLIF(SUM(p.penultimate_winner IN ('A','B')), 0), 2) AS penult_winrate_pct
FROM v_match_penultimate p
JOIN match_team_players mtp ON mtp.match_id = p.match_id
WHERE mtp.team_letter IN ('A','B')
GROUP BY mtp.player_id;

-- ---------------------------------------------------------------------------
-- PER-PLAYER: mini-game W/L/draw + win-rate.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_player_minigame AS
SELECT mtp.player_id,
       COUNT(*)                                                    AS mini_matches,
       SUM(mtp.team_letter = g.minigame_winner)                    AS mini_wins,
       SUM(g.minigame_winner IN ('A','B')
           AND mtp.team_letter <> g.minigame_winner)               AS mini_losses,
       SUM(g.minigame_winner = 'draw')                            AS mini_draws,
       ROUND(100 * SUM(mtp.team_letter = g.minigame_winner)
             / NULLIF(SUM(g.minigame_winner IN ('A','B')), 0), 2)  AS mini_winrate_pct
FROM v_match_minigame g
JOIN match_team_players mtp ON mtp.match_id = g.match_id
WHERE mtp.team_letter IN ('A','B')
GROUP BY mtp.player_id;

-- ---------------------------------------------------------------------------
-- PER-PLAYER: ties across every level (map, penultimate, mini-game, full match).
-- "Everything related to ties" in one place.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_player_ties AS
SELECT mtp.player_id,
       COUNT(DISTINCT CASE WHEN mm.winner = 'draw'       THEN mm.id END)        AS map_draws,
       COUNT(DISTINCT CASE WHEN pen.penultimate_winner = 'draw' THEN pen.match_id END) AS penultimate_draws,
       COUNT(DISTINCT CASE WHEN mg.minigame_winner = 'draw'     THEN mg.match_id END)  AS minigame_draws,
       COUNT(DISTINCT CASE WHEN ma.winner = 'draw'       THEN ma.id END)        AS match_draws
FROM match_team_players mtp
JOIN matches ma              ON ma.id = mtp.match_id
LEFT JOIN match_maps mm      ON mm.match_id = mtp.match_id
LEFT JOIN v_match_penultimate pen ON pen.match_id = mtp.match_id
LEFT JOIN v_match_minigame mg     ON mg.match_id = mtp.match_id
GROUP BY mtp.player_id;
