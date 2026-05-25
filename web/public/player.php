<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/Db.php';
require dirname(__DIR__) . '/src/View.php';

use Bizzy\Db;
use Bizzy\View;

$id = (int)($_GET['id'] ?? 0);
if ($id <= 0) { http_response_code(400); exit('bad player id'); }

$player = Db::one('SELECT * FROM v_player_totals WHERE player_id = :id', [':id' => $id]);
if ($player === null) { http_response_code(404); exit('player not found'); }

$byMode = Db::query(
    'SELECT g.name AS mode, ps.points, ps.playtime_s,
            ps.kills_common, ps.kills_special, ps.kills_tank, ps.kills_witch,
            ps.headshots, ps.deaths
     FROM player_stats ps
     JOIN gamemodes g ON g.id = ps.gamemode_id
     WHERE ps.player_id = :id AND ps.server_id = 0
     ORDER BY ps.points DESC',
    [':id' => $id]
);

$awards = Db::query(
    'SELECT a.name, SUM(pa.count) AS n
     FROM player_awards pa
     JOIN awards a ON a.id = pa.award_id
     WHERE pa.player_id = :id
     GROUP BY a.id
     ORDER BY n DESC',
    [':id' => $id]
);

ob_start();
?>
<p><strong>SteamID:</strong> <?= View::e($player['steamid']) ?>
   &middot; <strong>Last seen:</strong> <?= View::e($player['last_seen']) ?>
   &middot; <strong>Country:</strong> <?= View::e($player['country_code'] ?? '?') ?></p>

<h2>Totals</h2>
<table>
  <tr><th>Points</th><td class="num"><?= View::fmt((int)$player['points']) ?></td>
      <th>PPM</th><td class="num"><?= View::e($player['points_per_minute']) ?></td></tr>
  <tr><th>Playtime</th><td class="num"><?= View::dur((int)$player['playtime_s']) ?></td>
      <th>Kills</th><td class="num"><?= View::fmt((int)$player['kills']) ?></td></tr>
  <tr><th>Accuracy</th><td class="num"><?= View::e($player['accuracy_pct']) ?>%</td>
      <th>Headshot %</th><td class="num"><?= View::e($player['headshot_pct']) ?>%</td></tr>
  <tr><th>Damage dealt</th><td class="num"><?= View::fmt((int)$player['damage_dealt']) ?></td>
      <th>Damage taken</th><td class="num"><?= View::fmt((int)$player['damage_taken']) ?></td></tr>
</table>

<h2>By game mode</h2>
<table>
  <thead><tr><th>Mode</th><th class="num">Points</th><th class="num">Playtime</th>
             <th class="num">Common</th><th class="num">Special</th>
             <th class="num">Tank</th><th class="num">Witch</th><th class="num">HS</th><th class="num">Deaths</th></tr></thead>
  <tbody>
  <?php foreach ($byMode as $r): ?>
    <tr>
      <td><?= View::e($r['mode']) ?></td>
      <td class="num"><?= View::fmt((int)$r['points']) ?></td>
      <td class="num"><?= View::dur((int)$r['playtime_s']) ?></td>
      <td class="num"><?= View::fmt((int)$r['kills_common']) ?></td>
      <td class="num"><?= View::fmt((int)$r['kills_special']) ?></td>
      <td class="num"><?= View::fmt((int)$r['kills_tank']) ?></td>
      <td class="num"><?= View::fmt((int)$r['kills_witch']) ?></td>
      <td class="num"><?= View::fmt((int)$r['headshots']) ?></td>
      <td class="num"><?= View::fmt((int)$r['deaths']) ?></td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>

<h2>Awards</h2>
<table>
  <thead><tr><th>Award</th><th class="num">Count</th></tr></thead>
  <tbody>
    <?php foreach ($awards as $a): ?>
      <tr><td><?= View::e($a['name']) ?></td><td class="num"><?= View::fmt((int)$a['n']) ?></td></tr>
    <?php endforeach; ?>
  </tbody>
</table>
<?php
$body = ob_get_clean();
View::render('layout', ['title' => $player['name'], 'body' => $body]);
