<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/Db.php';
require dirname(__DIR__) . '/src/View.php';

use Bizzy\Db;
use Bizzy\View;

$rows = Db::query(
    'SELECT player_id, name, points, points_per_minute, accuracy_pct, headshot_pct, playtime_s
     FROM v_top_players
     ORDER BY points DESC
     LIMIT 50'
);

ob_start();
?>
<table>
  <thead>
    <tr>
      <th>#</th><th>Player</th>
      <th class="num">Points</th>
      <th class="num">PPM</th>
      <th class="num">Accuracy</th>
      <th class="num">HS %</th>
      <th class="num">Playtime</th>
    </tr>
  </thead>
  <tbody>
  <?php foreach ($rows as $i => $r): ?>
    <tr>
      <td><?= $i + 1 ?></td>
      <td><a href="player.php?id=<?= (int)$r['player_id'] ?>"><?= View::e($r['name']) ?></a></td>
      <td class="num"><?= View::fmt((int)$r['points']) ?></td>
      <td class="num"><?= View::e($r['points_per_minute']) ?></td>
      <td class="num"><?= View::e($r['accuracy_pct']) ?>%</td>
      <td class="num"><?= View::e($r['headshot_pct']) ?>%</td>
      <td class="num"><?= View::dur((int)$r['playtime_s']) ?></td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
<?php
$body = ob_get_clean();
View::render('layout', ['title' => 'Top players', 'body' => $body]);
