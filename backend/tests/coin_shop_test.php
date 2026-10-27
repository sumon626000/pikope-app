<?php
declare(strict_types=1);

// Coin pack bonus math (no database):
//   php tests/coin_shop_test.php
require dirname(__DIR__) . '/src/bootstrap.php';

use App\CoinShop;

$passed = 0;
function check(bool $ok, string $what): void
{
    global $passed;
    if (!$ok) {
        fwrite(STDERR, "FAIL: $what\n");
        exit(1);
    }
    $passed++;
}

/** Same formula as CoinDeposit::creditCoinsForBdt when bdt = pack face value and coinPerBdt = 1. */
function depositCoinsForPack(array $pack, int $coinPerBdt = 1): int
{
    $base = (int) $pack['coins'] * max(1, $coinPerBdt);
    $discount = CoinShop::effectiveBonusPercent($pack);
    return $base + intdiv($base * $discount, 100);
}

$tiers = [
    100 => [5, 105],
    200 => [10, 220],
    300 => [15, 345],
    500 => [20, 600],
    1000 => [20, 1200],
    5000 => [20, 6000],
    10000 => [30, 13000],
];

foreach ($tiers as $coins => [$pct, $receive]) {
    $pack = ['id' => "pack$coins", 'coins' => $coins, 'discountPercent' => $pct, 'priceCoins' => $coins];
    check(CoinShop::standardBonusPercent($coins) === $pct, "tier $coins → $pct%");
    check(CoinShop::effectiveBonusPercent($pack) === $pct, "effectiveBonusPercent pack $coins");
    check(CoinShop::receiveCoins($pack) === $receive, "receiveCoins $coins → $receive");
    check(depositCoinsForPack($pack) === $receive, "deposit credit $coins @ 1:1 BDT → $receive");
    check(CoinShop::receiveCoinsForCoinPurchase($pack) === $coins, "coin-priced buy $coins stays base (no deposit bonus)");
}

$free = ['id' => 'free', 'coins' => 50, 'discountPercent' => 0, 'priceCoins' => 0];
check(CoinShop::receiveCoinsForCoinPurchase($free) === CoinShop::receiveCoins($free), 'free pack uses receiveCoins');

$custom = ['id' => 'custom', 'coins' => 77, 'discountPercent' => 12, 'priceCoins' => 77];
check(CoinShop::standardBonusPercent(77) === 0, 'non-standard size has no tier');
check(CoinShop::effectiveBonusPercent($custom) === 12, 'non-standard uses pack discountPercent');
check(CoinShop::receiveCoins($custom) === 77 + intdiv(77 * 12, 100), 'custom pack bonus from discountPercent');

echo "OK - $passed coin shop checks passed\n";
