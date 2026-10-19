<?php
declare(strict_types=1);

// Checks that this server can run the backend: php bin/doctor.php
require dirname(__DIR__) . '/src/bootstrap.php';

use App\Config;
use App\Db;

$ok = true;
$line = static function (bool $pass, string $what, string $hint = '') use (&$ok): void {
    $ok = $ok && $pass;
    echo $pass ? '[ok]   ' : '[FAIL] ', $what, $pass || $hint === '' ? '' : "\n       -> $hint", "\n";
};

$line(PHP_VERSION_ID >= 80100, 'PHP ' . PHP_VERSION . ' (8.1 or newer needed)');
foreach (['pdo_mysql', 'json', 'mbstring', 'fileinfo'] as $ext) {
    $line(extension_loaded($ext), "extension $ext", "enable the $ext extension");
}
$line(PHP_INT_SIZE === 8, '64-bit PHP', 'a 64-bit build is required');
$line(is_file(dirname(__DIR__) . '/.env'), '.env present', 'copy .env.example to .env and fill it in');
try {
    $version = Db::pdo()->query('SELECT VERSION()')->fetchColumn();
    $line(true, "database reachable ($version)");
    $tables = Db::pdo()->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);
    $line(in_array('games', $tables, true) && in_array('rate_limits', $tables, true), 'schema installed', 'run: php bin/migrate.php');
} catch (Throwable $e) {
    $line(false, 'database reachable', $e->getMessage());
}
$uploads = dirname(__DIR__) . '/public/uploads/avatars';
$line(is_dir($uploads) && is_writable($uploads), 'uploads directory writable', "make $uploads writable by the web server user");
$url = Config::get('APP_URL');
$line(str_starts_with($url, 'https://') || str_contains($url, '10.0.2.2') || str_contains($url, 'localhost') || str_contains($url, '127.0.0.1'),
    "APP_URL is https ($url)", 'the app only talks to https servers (plain http is allowed for local development only)');
$line(Config::get('APP_DEBUG', '0') !== '1', 'APP_DEBUG is off', 'set APP_DEBUG=0 in production');
$line(Config::get('APP_TEST_HOOKS', '0') !== '1', 'APP_TEST_HOOKS is off', 'never enable test hooks in production');
$adminUser = trim((string) Config::get('ADMIN_USER', ''));
$adminPass = (string) Config::get('ADMIN_PASS', '');
$adminOff = $adminUser === '' && $adminPass === '';
$adminStrong = $adminUser !== '' && strlen($adminPass) >= 12;
$line($adminOff || $adminStrong, 'ADMIN_PASS is strong (or admin disabled)', 'use 12+ characters for ADMIN_PASS, or leave ADMIN_USER empty');
$cors = trim(Config::get('CORS_ORIGIN', ''));
$line($cors !== '*', 'CORS_ORIGIN is not *', 'leave CORS_ORIGIN empty for mobile-only, or set one https origin');
$line(true, 'Forgot-password OTP: configure in admin → SMS OTP (or SMS_LOG in .env for tests)');
// The physics must give the same answer on every server. The expected sum
// belongs to the current physics; update it if src/Game/Physics.php changes.
const PHYSICS_CHECKSUM = 13699.164638810336;
$w = App\Game\Physics::fromState(App\Game\Physics::rack([1, 2, 3, 4, 5], range(1, 15)));
$w->shoot(1.0, 0.0, 1.0, 0.0, 0.0);
$w->simulate();
$sum = 0.0;
foreach ($w->toState() as $b) {
    $sum += $b[0] + $b[1];
}
$line(abs($sum - PHYSICS_CHECKSUM) < 1e-9, 'physics self-check', 'this PHP build computes floats differently; do not use it');
$fcm = trim(Config::get('FCM_SERVER_KEY', ''));
$prod = str_starts_with($url, 'https://') && !str_contains($url, 'localhost') && !str_contains($url, '127.0.0.1');
if ($prod && $fcm === '') {
    echo "[warn] FCM_SERVER_KEY empty — device push from admin will not deliver (in-app inbox still works)\n";
}
try {
    $drift = (int) Db::one(
        "SELECT COUNT(*) AS n FROM users u
         WHERE (
           EXISTS (SELECT 1 FROM wallet_tx t WHERE t.user_id = u.id AND t.currency = 'coins')
           AND u.coins <> (SELECT t.balance_after FROM wallet_tx t
                           WHERE t.user_id = u.id AND t.currency = 'coins' ORDER BY t.id DESC LIMIT 1)
         ) OR (
           EXISTS (SELECT 1 FROM wallet_tx t WHERE t.user_id = u.id AND t.currency = 'gems')
           AND u.gems <> (SELECT t.balance_after FROM wallet_tx t
                          WHERE t.user_id = u.id AND t.currency = 'gems' ORDER BY t.id DESC LIMIT 1)
         )"
    )['n'];
    $line($drift === 0, 'wallet balances match ledger', 'run: php bin/reconcile_wallet.php');
} catch (Throwable) {
    // DB check above may already have failed.
}

echo $ok ? "\nReady.\n" : "\nNot ready - fix the items marked FAIL.\n";
exit($ok ? 0 : 1);
