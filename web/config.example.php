<?php
return [
    'db' => [
        'host'     => '127.0.0.1',
        'port'     => 3306,
        'database' => 'bizzymod_stats',
        'user'     => 'bizzymod_stats',
        'password' => 'CHANGE-ME',
        'charset'  => 'utf8mb4',
    ],
    'site' => [
        'name'    => 'bizzymod-stats',
        'refresh' => 0, // seconds; 0 disables auto-refresh on index
    ],
];
