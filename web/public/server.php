<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/Db.php';
require dirname(__DIR__) . '/src/View.php';

use Bizzy\Db;
use Bizzy\View;

$id = (int)($_GET['id'] ?? 0);
ob_start();

if ($id === 0) {
    $servers = Db::query('SELECT id, name, address, game_id, last_seen FROM servers ORDER BY last_seen DESC');
    ?>
    <table>
      <thead><tr><th>Server</th><th>Address</th><th>Last seen</th></tr></thead>
      <tbody>
        <?php foreach ($servers as $s): ?>
          <tr>
            <td><a href="server.php?id=<?= (int)$s['id'] ?>"><?= View::e($s['name']) ?></a></td>
            <td><?= View::e($s['address'] ?? '—') ?></td>
            <td><?= View::e($s['last_seen']) ?></td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
    <?php
    $body = ob_get_clean();
    View::render('layout', ['title' => 'Servers', 'body' => $body]);
    exit;
}

$server = Db::one('SELECT * FROM servers WHERE id = :id', [':id' => $id]);
if ($server === null) { http_response_code(404); exit('server not found'); }

$recent = Db::query(
    'SELECT s.started_at, s.ended_at, s.duration_s, s.points, s.kills,
            CAST(p.name AS CHAR) AS player_name, g.name AS gamemode
     FROM sessions s
     JOIN players p ON p.id = s.player_id
     JOIN gamemodes g ON g.id = s.gamemode_id
     WHERE s.server_id = :id
     ORDER BY s.started_at DESC
     LIMIT 50',
    [':id' => $id]
);

?>
<p><strong>Address:</strong> <?= View::e($server['address'] ?? '—') ?>
   &middot; <strong>First seen:</strong> <?= View::e($server['first_seen']) ?>
   &middot; <strong>Last seen:</strong> <?= View::e($server['last_seen']) ?></p>

<h2>Recent sessions</h2>
<table>
  <thead><tr><th>Started</th><th>Player</th><th>Mode</th><th class="num">Duration</th>
             <th class="num">Points</th><th class="num">Kills</th></tr></thead>
  <tbody>
  <?php foreach ($recent as $s): ?>
    <tr>
      <td><?= View::e($s['started_at']) ?></td>
      <td><?= View::e($s['player_name']) ?></td>
      <td><?= View::e($s['gamemode']) ?></td>
      <td class="num"><?= View::dur((int)$s['duration_s']) ?></td>
      <td class="num"><?= View::fmt((int)$s['points']) ?></td>
      <td class="num"><?= View::fmt((int)$s['kills']) ?></td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
<?php
$body = ob_get_clean();
View::render('layout', ['title' => $server['name'], 'body' => $body]);
