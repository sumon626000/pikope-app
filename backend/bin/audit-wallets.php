<?php

declare(strict_types=1);

/**
 * Checks every player's coin balance against the wallet ledger: the balance
 * must equal the sum of their wallet_tx rows (players created before the
 * welcome grant was logged get the configured start coins on top). Any
 * difference means coins moved outside Economy::move - which is the only
 * legitimate way - so print it and exit non-zero. Run it from cron or the
 * admin page: `php bin/audit-wallets.php [--fix]` (--fix rewrites the
 * balance from the ledger and logs the correction).
 */

require __DIR__ . '/../src/bootstrap.php';

use App\Db;
use App\Economy;

$fix = in_array('--fix', $argv, true);
$start = (int) Economy::config()['startCoins'];
$rows = Db::all(
    "SELECT u.id, u.display_name, u.coins,
            COALESCE((SELECT SUM(t.amount) FROM wallet_tx t WHERE t.user_id = u.id AND t.currency = 'coins'), 0) AS ledger,
            EXISTS(SELECT 1 FROM wallet_tx w WHERE w.user_id = u.id AND w.reason = 'welcome') AS welcomed
     FROM users u WHERE u.is_bot = 0"
);
$bad = 0;
foreach ($rows as $r) {
    $expected = (int) $r['ledger'] + ((int) $r['welcomed'] === 1 ? 0 : $start);
    if ((int) $r['coins'] === $expected) {
        continue;
    }
    $bad++;
    printf("user %d (%s): balance %d, ledger says %d (diff %+d)\n", $r['id'], $r['display_name'], $r['coins'], $expected, $r['coins'] - $expected);
    if ($fix) {
        Db::transaction(static function () use ($r, $expected): void {
            Db::run('UPDATE users SET coins = ? WHERE id = ?', [$expected, $r['id']]);
            Db::run("INSERT INTO wallet_tx (user_id, currency, amount, balance_after, reason) VALUES (?, 'coins', 0, ?, 'audit_fix')", [$r['id'], $expected]);
        });
        echo "  fixed\n";
    }
}
printf("%d players checked, %d mismatch%s\n", count($rows), $bad, $bad === 1 ? '' : 'es');
exit($bad === 0 || $fix ? 0 : 1);
