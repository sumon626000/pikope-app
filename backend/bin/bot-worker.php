<?php
declare(strict_types=1);

// Stand-in players: seats bots in public rooms nobody else joined, then plays
// their turns. Run exactly one instance (the "bots" service in Docker):
//   php bin/bot-worker.php              runs until stopped
//   php bin/bot-worker.php --seconds=60 stops after a minute (tests)
// BOT_FILL=0 turns seating off; BOT_FILL_SECONDS is the wait (default 5).
require dirname(__DIR__) . '/src/bootstrap.php';

use App\BotService;
use App\Db;
use App\GameService;

if (PHP_SAPI !== 'cli') {
    exit(1);
}

$opts = getopt('', ['seconds::']);
$until = isset($opts['seconds']) ? microtime(true) + (float) $opts['seconds'] : INF;

BotService::ensure();
echo '[bots] running; fill after ', BotService::fillSeconds(), "s\n";
$lastFill = 0.0;
while (microtime(true) < $until) {
    $now = microtime(true);
    try {
        if ($now - $lastFill >= 1.0) {
            $lastFill = $now;
            $started = BotService::fillRooms();
            if ($started > 0) {
                echo "[bots] seated bots in $started room(s)\n";
            }
        }
        foreach (Db::all("SELECT id FROM games WHERE status = 'active' AND has_bots = 1") as $row) {
            GameService::driveBot((int) $row['id']);
        }
    } catch (\PDOException $e) {
        Db::reset();
        error_log('[bots] database: ' . $e->getMessage());
        sleep(1);
    } catch (\Throwable $e) {
        error_log('[bots] ' . $e::class . ': ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
    }
    usleep(200000);
}
