<?php
declare(strict_types=1);

namespace App;

/** Admin-configured coin packs. Discount adds bonus coins on top of the base amount. */
final class CoinShop
{
    public const DEFAULTS = [
        'globalDiscountPercent' => 0,
        'packs' => [
            ['id' => 'pack100', 'name' => '100', 'coins' => 100, 'discountPercent' => 5, 'priceCoins' => 100, 'active' => true, 'sort' => 0],
            ['id' => 'pack200', 'name' => '200', 'coins' => 200, 'discountPercent' => 7, 'priceCoins' => 200, 'active' => true, 'sort' => 1],
            ['id' => 'pack300', 'name' => '300', 'coins' => 300, 'discountPercent' => 10, 'priceCoins' => 300, 'active' => true, 'sort' => 2],
            ['id' => 'pack500', 'name' => '500', 'coins' => 500, 'discountPercent' => 15, 'priceCoins' => 500, 'active' => true, 'sort' => 3],
            ['id' => 'pack1000', 'name' => '1000', 'coins' => 1000, 'discountPercent' => 20, 'priceCoins' => 1000, 'active' => true, 'sort' => 4],
            ['id' => 'pack5000', 'name' => '5000', 'coins' => 5000, 'discountPercent' => 25, 'priceCoins' => 5000, 'active' => true, 'sort' => 5],
            ['id' => 'pack10000', 'name' => '10000', 'coins' => 10000, 'discountPercent' => 30, 'priceCoins' => 10000, 'active' => true, 'sort' => 6],
        ],
    ];

    /** @var array<string,mixed>|null */
    private static ?array $config = null;

    /** @return array{globalDiscountPercent:int,packs:list<array<string,mixed>>} */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'coin_shop'");
        $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
        $merged = array_merge(self::DEFAULTS, array_intersect_key($saved, self::DEFAULTS));
        if (!is_array($merged['packs'] ?? null)) {
            $merged['packs'] = self::DEFAULTS['packs'];
        }
        self::$config = self::applyStandardBonusesIfUnset(self::normalize($merged));
        return self::$config;
    }

    /** @param array{globalDiscountPercent:int,packs:list<array<string,mixed>>} $c */
    private static function applyStandardBonusesIfUnset(array $c): array
    {
        foreach ($c['packs'] as $p) {
            if ((int) ($p['discountPercent'] ?? 0) > 0) {
                return $c;
            }
        }
        $byId = [];
        foreach (self::DEFAULTS['packs'] as $d) {
            $byId[(string) $d['id']] = (int) $d['discountPercent'];
        }
        $out = [];
        foreach ($c['packs'] as $p) {
            $id = (string) ($p['id'] ?? '');
            if (isset($byId[$id])) {
                $p['discountPercent'] = $byId[$id];
            }
            $out[] = $p;
        }
        $c['packs'] = $out;
        return $c;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        $clean = self::normalize($raw);
        Db::run("INSERT INTO settings (k, v) VALUES ('coin_shop', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)", [json_encode($clean)]);
        self::$config = null;
    }

    /** Coins the player receives (base + per-pack bonus % only, e.g. 100 @ 5% → 105). */
    public static function receiveCoins(array $pack, ?int $global = null): int
    {
        unset($global);
        $base = (int) $pack['coins'];
        $bonus = max(0, min(100, (int) $pack['discountPercent']));
        return $base + intdiv($base * $bonus, 100);
    }

    /** @return list<array<string,mixed>> */
    public static function publicPacks(int $userId): array
    {
        $c = self::config();
        $packs = $c['packs'];
        usort($packs, static fn (array $a, array $b): int => ($a['sort'] <=> $b['sort']) ?: strcmp($a['id'], $b['id']));
        $out = [];
        foreach ($packs as $p) {
            if (!(bool) ($p['active'] ?? true)) {
                continue;
            }
            $receive = self::receiveCoins($p);
            $free = (int) $p['priceCoins'] <= 0;
            $claimed = $free && self::freeClaimed($userId, (string) $p['id']);
            $out[] = [
                'id' => $p['id'],
                'name' => $p['name'],
                'coins' => (int) $p['coins'],
                'discountPercent' => (int) $p['discountPercent'],
                'globalDiscountPercent' => 0,
                'receiveCoins' => $receive,
                'priceCoins' => (int) $p['priceCoins'],
                'free' => $free,
                'claimed' => $claimed,
            ];
        }
        return $out;
    }

    /** @return array{user:array<string,mixed>,receiveCoins:int} */
    public static function buy(array $user, string $packId): array
    {
        return Db::transaction(static function () use ($user, $packId): array {
            $uid = (int) $user['id'];
            Db::one('SELECT id FROM users WHERE id = ? FOR UPDATE', [$uid]);
            $pack = self::findPack($packId);
            if ($pack === null || !(bool) ($pack['active'] ?? true)) {
                throw ApiError::notFound('No such coin pack');
            }
            $receive = self::receiveCoins($pack);
            $price = (int) $pack['priceCoins'];
            if ($price <= 0) {
                if (self::freeClaimed($uid, $packId)) {
                    throw ApiError::conflict('You already claimed this pack', 'already_claimed');
                }
            } else {
                Economy::move($uid, -$price, 'coin_shop_buy:' . substr($packId, 0, 20));
            }
            Economy::move($uid, $receive, 'coin_shop:' . substr($packId, 0, 20));
            Db::run(
                'INSERT INTO coin_shop_purchases (user_id, pack_id, coins, price_coins) VALUES (?, ?, ?, ?)',
                [$uid, $packId, $receive, max(0, $price)]
            );
            return [
                'receiveCoins' => $receive,
                'user' => Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$uid])),
            ];
        });
    }

    private static function freeClaimed(int $userId, string $packId): bool
    {
        return Db::one(
            'SELECT id FROM coin_shop_purchases WHERE user_id = ? AND pack_id = ? AND price_coins = 0 LIMIT 1',
            [$userId, $packId]
        ) !== null;
    }

    /** @return array<string,mixed>|null */
    private static function findPack(string $id): ?array
    {
        foreach (self::config()['packs'] as $p) {
            if (($p['id'] ?? '') === $id) {
                return $p;
            }
        }
        return null;
    }

    /** @param array<string,mixed> $raw @return array{globalDiscountPercent:int,packs:list<array<string,mixed>>} */
    private static function normalize(array $raw): array
    {
        $global = (int) ($raw['globalDiscountPercent'] ?? 0);
        if ($global < 0 || $global > 100) {
            throw ApiError::badRequest('globalDiscountPercent must be 0-100');
        }
        $packs = $raw['packs'] ?? [];
        if (!is_array($packs)) {
            throw ApiError::badRequest('packs must be a list');
        }
        $clean = [];
        $ids = [];
        foreach ($packs as $p) {
            if (!is_array($p)) {
                throw ApiError::badRequest('Each pack must be an object');
            }
            $id = strtolower(trim((string) ($p['id'] ?? '')));
            if (!preg_match('/^[a-z0-9_-]{1,32}$/', $id)) {
                throw ApiError::badRequest('Pack id must be 1-32 letters, numbers, _ or -');
            }
            if (isset($ids[$id])) {
                throw ApiError::badRequest("Duplicate pack id: $id");
            }
            $ids[$id] = true;
            $name = trim((string) ($p['name'] ?? ''));
            if ($name === '' || strlen($name) > 32) {
                throw ApiError::badRequest('Pack name must be 1-32 characters');
            }
            $coins = (int) ($p['coins'] ?? 0);
            if ($coins < 1 || $coins > 100000000) {
                throw ApiError::badRequest('Pack coins must be 1-100000000');
            }
            $discount = (int) ($p['discountPercent'] ?? 0);
            if ($discount < 0 || $discount > 100) {
                throw ApiError::badRequest('Pack discount must be 0-100');
            }
            $price = (int) ($p['priceCoins'] ?? 0);
            if ($price < 0 || $price > 100000000) {
                throw ApiError::badRequest('priceCoins must be 0-100000000');
            }
            $clean[] = [
                'id' => $id,
                'name' => $name,
                'coins' => $coins,
                'discountPercent' => $discount,
                'priceCoins' => $price,
                'active' => (bool) ($p['active'] ?? true),
                'sort' => (int) ($p['sort'] ?? 0),
            ];
        }
        if ($clean === []) {
            foreach (self::DEFAULTS['packs'] as $p) {
                $clean[] = $p;
            }
        }
        return ['globalDiscountPercent' => $global, 'packs' => $clean];
    }
}
