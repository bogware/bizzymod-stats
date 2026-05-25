<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/Db.php';
require dirname(__DIR__) . '/src/View.php';

use Bizzy\Db;
use Bizzy\View;

$id = (int)($_GET['id'] ?? 0);
if ($id <= 0) { http_response_code(400); exit('bad match id'); }

$match = Db::one(
    'SELECT vms.*, mt_a.maps_won AS a_maps, mt_b.maps_won AS b_maps,
            mt_a.rounds_won AS a_rounds, mt_b.rounds_won AS b_rounds
     FROM v_match_summary vms
     LEFT JOIN match_teams mt_a ON mt_a.match_id = vms.match_id AND mt_a.team_letter = "A"
     LEFT JOIN match_teams mt_b ON mt_b.match_id = vms.match_id AND mt_b.team_letter = "B"
     WHERE vms.match_id = :id',
    [':id' => $id]
);
if ($match === null) { http_response_code(404); exit('match not found'); }

$roster = Db::query(
    'SELECT team_letter, player_id, player_name, joined_round, left_round, time_on_team_s
     FROM v_match_team_roster
     WHERE match_id = :id
     ORDER BY team_letter, joined_round, player_name',
    [':id' => $id]
);

$rosterByLetter = ['A' => [], 'B' => []];
foreach ($roster as $r) $rosterByLetter[$r['team_letter']][] = $r;

$maps = Db::query(
    'SELECT mm.id AS match_map_id, mm.ordinal, m.code AS map_code, m.display_name,
            mm.team_a_score, mm.team_b_score, mm.winner,
            mm.started_at, mm.ended_at
     FROM match_maps mm
     JOIN maps m ON m.id = mm.map_id
     WHERE mm.match_id = :id
     ORDER BY mm.ordinal',
    [':id' => $id]
);

$roundsByMap = [];
foreach ($maps as $m) {
    $roundsByMap[$m['match_map_id']] = Db::query(
        'SELECT id, round_index, survivor_team, started_at, ended_at, duration_s,
                engine_score, plugin_score_surv, plugin_score_inf,
                survivors_left, tank_appeared, witch_appeared, end_reason
         FROM match_rounds
         WHERE match_map_id = :id
         ORDER BY round_index',
        [':id' => $m['match_map_id']]
    );
}

ob_start();
?>
<p>
  <strong>Server:</strong> <?= View::e($match['server_name']) ?>
  &middot; <strong>Mode:</strong> <?= View::e($match['gamemode']) ?>
  &middot; <strong>Campaign:</strong> <?= View::e($match['campaign'] ?? '—') ?>
  &middot; <strong>Started:</strong> <?= View::e($match['started_at']) ?>
  <?php if ($match['ended_at']): ?>
  &middot; <strong>Ended:</strong> <?= View::e($match['ended_at']) ?>
  <?php endif; ?>
</p>

<h2>Final</h2>
<table>
  <thead><tr><th>Team</th><th class="num">Score</th><th class="num">Maps won</th><th class="num">Rounds won</th></tr></thead>
  <tbody>
    <tr<?= $match['winner'] === 'A' ? ' style="background:#e8f7e8"' : '' ?>>
      <td>Team A</td>
      <td class="num"><?= View::fmt((int)$match['team_a_score']) ?></td>
      <td class="num"><?= (int)($match['a_maps'] ?? 0) ?></td>
      <td class="num"><?= (int)($match['a_rounds'] ?? 0) ?></td>
    </tr>
    <tr<?= $match['winner'] === 'B' ? ' style="background:#e8f7e8"' : '' ?>>
      <td>Team B</td>
      <td class="num"><?= View::fmt((int)$match['team_b_score']) ?></td>
      <td class="num"><?= (int)($match['b_maps'] ?? 0) ?></td>
      <td class="num"><?= (int)($match['b_rounds'] ?? 0) ?></td>
    </tr>
  </tbody>
</table>
<p><strong>Winner:</strong> <?= View::e($match['winner'] ?? '—') ?>
   <?php if ($match['end_reason']): ?>(<?= View::e($match['end_reason']) ?>)<?php endif; ?></p>

<h2>Rosters</h2>
<div style="display:flex;gap:2rem;flex-wrap:wrap">
  <?php foreach (['A', 'B'] as $L): ?>
    <div style="flex:1;min-width:280px">
      <h3>Team <?= $L ?></h3>
      <table>
        <?php foreach ($rosterByLetter[$L] as $p): ?>
          <tr>
            <td><a href="player.php?id=<?= (int)$p['player_id'] ?>"><?= View::e($p['player_name']) ?></a></td>
            <td class="num">
              <?php if ((int)$p['joined_round'] > 0): ?>
                joined R<?= (int)$p['joined_round'] ?>
              <?php endif; ?>
              <?php if ($p['left_round']): ?>
                · left R<?= (int)$p['left_round'] ?>
              <?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
      </table>
    </div>
  <?php endforeach; ?>
</div>

<h2>Maps</h2>
<?php foreach ($maps as $m): ?>
  <h3>Map <?= (int)$m['ordinal'] ?>: <?= View::e($m['display_name'] ?? $m['map_code']) ?>
      <small style="color:#888">
        A <?= View::fmt((int)$m['team_a_score']) ?> &mdash; B <?= View::fmt((int)$m['team_b_score']) ?>
        · winner: <?= View::e($m['winner']) ?>
      </small>
  </h3>
  <table>
    <thead>
      <tr>
        <th>Round</th><th>Survivors</th><th class="num">Engine score</th>
        <th class="num">Plugin surv</th><th class="num">Plugin inf</th>
        <th class="num">Surv left</th>
        <th>Specials</th><th>End</th>
      </tr>
    </thead>
    <tbody>
      <?php foreach ($roundsByMap[$m['match_map_id']] as $r): ?>
        <tr>
          <td><?= (int)$r['round_index'] ?></td>
          <td>Team <?= View::e($r['survivor_team']) ?></td>
          <td class="num"><?= View::fmt((int)$r['engine_score']) ?></td>
          <td class="num"><?= View::fmt((int)$r['plugin_score_surv']) ?></td>
          <td class="num"><?= View::fmt((int)$r['plugin_score_inf']) ?></td>
          <td class="num"><?= (int)$r['survivors_left'] ?></td>
          <td><?= $r['tank_appeared'] ? 'tank ' : '' ?><?= $r['witch_appeared'] ? 'witch' : '' ?></td>
          <td><?= View::e($r['end_reason'] ?? '—') ?></td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
<?php endforeach; ?>
<?php
$body = ob_get_clean();
View::render('layout', ['title' => 'Match #' . $id, 'body' => $body]);
