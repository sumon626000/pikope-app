<?php
declare(strict_types=1);

// WebSocket server for live play. Keep it running (systemd / supervisor):
//   php bin/ws-server.php
// Listens on WS_HOST:WS_PORT (default 127.0.0.1:8081); put it behind nginx or
// Apache so players reach it as wss://your-domain/ws. See deploy/DEPLOY.md.
require dirname(__DIR__) . '/src/bootstrap.php';

use App\Config;
use App\Ws\Server;

if (PHP_SAPI !== 'cli') {
    exit(1);
}
set_time_limit(0);

$host = Config::get('WS_HOST', '127.0.0.1');
$port = Config::int('WS_PORT', 8081);
$server = new Server($host, $port);
if (function_exists('pcntl_signal')) {
    pcntl_async_signals(true);
    foreach ([SIGTERM, SIGINT] as $signal) {
        pcntl_signal($signal, static fn () => $server->stop());
    }
}
fwrite(STDERR, '[ws] listening on ' . $host . ':' . $port . "\n");
$server->run();
