<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/Db.php';
require dirname(__DIR__) . '/src/View.php';

use Bizzy\Db;
use Bizzy\View;

$awards = Db::query(
    "SELECT id, code, name, category FROM awards ORDER BY display_order, name"
);

$leaders = [];
foreach ($awards as $a) {
    $leaders[$a['id']] = Db::query(
        'SELECT p.id AS player_id, CAST(p.name AS CHAR) AS name, SUM(pa.count) AS n
         FROM player_awards pa
         JOIN players p ON p.id = pa.player_id
         WHERE pa.award_id = :aid
         GROUP BY p.id
         ORDER BY n DESC
         LIMIT 3',
        [':aid' => $a['id']]
    );
}

ob_start();
?>
<?php foreach ($awards as $a): ?>
  <h2><?= View::e($a['name']) ?> <small style="color:#888"><?= View::e($a['category']) ?></small></h2>
  <table>
    <?php foreach ($leaders[$a['id']] as $i => $row): ?>
      <tr>
        <td><?= $i + 1 ?>.</td>
        <td><a href="player.php?id=<?= (int)$row['player_id'] ?>"><?= View::e($row['name']) ?></a></td>
        <td class="num"><?= View::fmt((int)$row['n']) ?></td>
      </tr>
    <?php endforeach; ?>
  </table>
<?php endforeach; ?>
<?php
$body = ob_get_clean();
View::render('layout', ['title' => 'Awards', 'body' => $body]);
