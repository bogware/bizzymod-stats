<?php
declare(strict_types=1);

namespace Bizzy;

final class View
{
    public static function render(string $template, array $vars = []): void
    {
        $cfg = require dirname(__DIR__) . '/config.php';
        $vars['site'] = $cfg['site'];
        extract($vars, EXTR_SKIP);
        require dirname(__DIR__) . '/templates/' . $template . '.phtml';
    }

    public static function e(string|int|float|null $v): string
    {
        return htmlspecialchars((string)$v, ENT_QUOTES | ENT_HTML5, 'UTF-8');
    }

    public static function fmt(int|float $n): string
    {
        return number_format((float)$n);
    }

    public static function dur(int $seconds): string
    {
        $h = intdiv($seconds, 3600);
        $m = intdiv($seconds % 3600, 60);
        return $h > 0 ? sprintf('%dh %dm', $h, $m) : sprintf('%dm', $m);
    }
}
