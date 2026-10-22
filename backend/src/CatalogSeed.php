<?php
declare(strict_types=1);

namespace App;

/** Applies the play-bet and shop-pack list once. Admin edits after that are kept. */
final class CatalogSeed
{
    private const MARK = '20261020-bets-packs';

    /** @var list<int> */
    private const STAKES = [25, 50, 100, 300, 500, 1000, 5000, 10000];

    /** @var list<int> */
    private const PACKS = [100, 200, 300, 500, 1000, 5000, 10000];

    public static function apply(): void
    {
        static $done = false;
        if ($done) {
            return;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'catalog_seed'");
        if ($row !== null && (string) $row['v'] === self::MARK) {
            return;
        }
        self::stakes();
        self::packs();
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('catalog_seed', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [self::MARK]
        );
        $done = true;
    }

    private static function stakes(): void
    {
        $row = Db::one("SELECT v FROM settings WHERE k = 'economy'");
        $data = $row === null ? Economy::DEFAULTS : (json_decode((string) $row['v'], true) ?: []);
        if (!is_array($data)) {
            $data = Economy::DEFAULTS;
        }
        $data['billiardStakes'] = self::STAKES;
        $data['pokerStakes'] = self::STAKES;
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('economy', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode($data)]
        );
    }

    private static function packs(): void
    {
        $row = Db::one("SELECT v FROM settings WHERE k = 'coin_shop'");
        $data = $row === null ? CoinShop::DEFAULTS : (json_decode((string) $row['v'], true) ?: []);
        if (!is_array($data)) {
            $data = CoinShop::DEFAULTS;
        }
        $packs = [];
        foreach (self::PACKS as $i => $amount) {
            $packs[] = [
                'id' => 'pack' . $amount,
                'name' => (string) $amount,
                'coins' => $amount,
                'discountPercent' => 0,
                'priceCoins' => $amount,
                'active' => true,
                'sort' => $i,
            ];
        }
        $data['packs'] = $packs;
        if (!isset($data['globalDiscountPercent'])) {
            $data['globalDiscountPercent'] = 0;
        }
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('coin_shop', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode($data)]
        );
    }
}
