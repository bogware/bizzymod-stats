<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/Db.php';
require dirname(__DIR__) . '/src/View.php';

use Bizzy\Db;
use Bizzy\View;

$rows = Db::query(
    'SELECT match_id, server_name, gamemode, campaign, started_at, ended_at,
            maps_played, rounds_played, team_a_score, team_b_score, winner
     FROM v_match_summary
     ORDER BY started_at DESC
     LIMIT 50'
);

ob_start();
?>
<table>
  <thead>
    <tr>
      <th>Started</th><th>Server</th><th>Mode</th><th>Campaign</th>
      <th class="num">Maps</th><th class="num">Rounds</th>
      <th class="num">Team A</th><th class="num">Team B</th><th>Winner</th>
    </tr>
  </thead>
  <tbody>
  <?php foreach ($rows as $r): ?>
    <tr>
      <td><a href="match.php?id=<?= (int)$r['match_id'] ?>"><?= View::e($r['started_at']) ?></a></td>
      <td><?= View::e($r['server_name']) ?></td>
      <td><?= View::e($r['gamemode']) ?></td>
      <td><?= View::e($r['campaign'] ?? '—') ?></td>
      <td class="num"><?= (int)$r['maps_played'] ?></td>
      <td class="num"><?= (int)$r['rounds_played'] ?></td>
      <td class="num"><?= View::fmt((int)$r['team_a_score']) ?></td>
      <td class="num"><?= View::fmt((int)$r['team_b_score']) ?></td>
      <td><strong><?= View::e($r['winner'] ?? '—') ?></strong></td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
<p style="margin-top:1rem;color:#888;font-size:.85rem">
  Versus matches are recorded automatically by the plugin. A match spans one
  campaign with stable teams; team identity persists across the engine's
  side-swap between halves.
</p>
<?php
$body = ob_get_clean();
View::render('layout', ['title' => 'Recent matches', 'body' => $body]);
