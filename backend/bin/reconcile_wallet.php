<?php
declare(strict_types=1);

// Compare users.coins/gems to the latest wallet_tx row and ledger chain integrity.
// Read-only: php bin/reconcile_wallet.php
// Exit 1 if any mismatch (for cron alerting).
require dirname(__DIR__) . '/src/bootstrap.php';

use App\Db;

if (PHP_SAPI !== 'cli') {
    exit(1);
}

$limit = 5000;
foreach ($argv as $arg) {
    if (str_starts_with($arg, '--limit=')) {
        $limit = max(1, min(50000, (int) substr($arg, 8)));
    }
}

/** @return list<array<string,mixed>> */
function walletMismatches(int $limit): array
{
    $out = [];
    $users = Db::all(
        'SELECT id, coins, gems FROM users ORDER BY id DESC LIMIT ' . $limit
    );
    foreach ($users as $u) {
        $uid = (int) $u['id'];
        foreach (['coins' => 'coins', 'gems' => 'gems'] as $column => $currency) {
            $rows = Db::all(
                'SELECT id, amount, balance_after FROM wallet_tx WHERE user_id = ? AND currency = ? ORDER BY id ASC',
                [$uid, $currency]
            );
            if ($rows === []) {
                continue;
            }
            $running = 0;
            $chainOk = true;
            foreach ($rows as $r) {
                $running += (int) $r['amount'];
                if ($running !== (int) $r['balance_after']) {
                    $chainOk = false;
                    break;
                }
            }
            $ledger = (int) $rows[array_key_last($rows)]['balance_after'];
            $balance = (int) $u[$column];
            if (!$chainOk || $ledger !== $balance) {
                $out[] = [
                    'userId' => $uid,
                    'currency' => $currency,
                    'balance' => $balance,
                    'ledger' => $ledger,
                    'chainOk' => $chainOk,
                    'txCount' => count($rows),
                ];
            }
        }
    }
    return $out;
}

try {
    Db::pdo()->query('SELECT 1');
} catch (Throwable $e) {
    fwrite(STDERR, "database: {$e->getMessage()}\n");
    exit(1);
}

$bad = walletMismatches($limit);
echo 'checked users (newest first): up to ', $limit, "\n";
echo 'mismatches: ', count($bad), "\n";
foreach ($bad as $row) {
    echo '  user ', $row['userId'], ' ', $row['currency'],
        ' balance=', $row['balance'], ' ledger=', $row['ledger'],
        $row['chainOk'] ? '' : ' CHAIN_BROKEN',
        ' (', $row['txCount'], " tx)\n";
}

exit($bad === [] ? 0 : 1);
