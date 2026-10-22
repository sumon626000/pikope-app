<?php
declare(strict_types=1);

namespace App;

/** Shop prices for cues and boards (pool / carrom / ludo). Stored in settings.item_prices. */
final class ItemCatalog
{
    /** @var array{cues: array<string,int>, boards: array<string, array<string,int>>}|null */
    private static ?array $config = null;

    /** @return array{cues: array<string,int>, boards: array<string, array<string,int>>} */
    public static function defaults(): array
    {
        $cues = [];
        foreach (Economy::CUES as $id => $meta) {
            $cues[$id] = (int) $meta['price'];
        }
        return ['cues' => $cues, 'boards' => Economy::BOARDS];
    }

    /** @return array{cues: array<string,int>, boards: array<string, array<string,int>>} */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $base = self::defaults();
        $row = Db::one("SELECT v FROM settings WHERE k = 'item_prices'");
        $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
        if (!is_array($saved)) {
            $saved = [];
        }
        $cues = $base['cues'];
        if (is_array($saved['cues'] ?? null)) {
            foreach ($saved['cues'] as $id => $price) {
                if (isset($cues[$id]) && (is_int($price) || (is_string($price) && ctype_digit($price)))) {
                    $cues[$id] = max(0, min(100_000_000, (int) $price));
                }
            }
        }
        $boards = $base['boards'];
        if (is_array($saved['boards'] ?? null)) {
            foreach ($boards as $kind => $items) {
                $over = $saved['boards'][$kind] ?? null;
                if (!is_array($over)) {
                    continue;
                }
                foreach ($items as $id => $default) {
                    if (!array_key_exists($id, $over)) {
                        continue;
                    }
                    $p = $over[$id];
                    if (is_int($p) || (is_string($p) && ctype_digit($p))) {
                        $boards[$kind][$id] = max(0, min(100_000_000, (int) $p));
                    }
                }
            }
        }
        self::$config = ['cues' => $cues, 'boards' => $boards];
        return self::$config;
    }

    /** @param array{cues?: array<string,mixed>, boards?: array<string, array<string,mixed>>} $raw */
    public static function save(array $raw): void
    {
        $base = self::defaults();
        $cues = [];
        foreach ($base['cues'] as $id => $default) {
            $p = $raw['cues'][$id] ?? $default;
            if (!is_int($p) && !(is_string($p) && ctype_digit($p))) {
                throw ApiError::badRequest("Invalid price for cue $id");
            }
            $p = (int) $p;
            if ($p < 0 || $p > 100_000_000) {
                throw ApiError::badRequest("Cue $id price must be 0-100000000");
            }
            $cues[$id] = $p;
        }
        $boards = [];
        foreach ($base['boards'] as $kind => $items) {
            $boards[$kind] = [];
            foreach ($items as $id => $default) {
                $p = $raw['boards'][$kind][$id] ?? $default;
                if (!is_int($p) && !(is_string($p) && ctype_digit($p))) {
                    throw ApiError::badRequest("Invalid price for $kind board $id");
                }
                $p = (int) $p;
                if ($p < 0 || $p > 100_000_000) {
                    throw ApiError::badRequest("Board $kind/$id price must be 0-100000000");
                }
                $boards[$kind][$id] = $p;
            }
        }
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('item_prices', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode(['cues' => $cues, 'boards' => $boards])]
        );
        self::$config = null;
    }

    /** @return array{name:string,price:int,currency:string} */
    public static function cue(string $id): array
    {
        $meta = Economy::CUES[$id] ?? throw ApiError::notFound('No such cue');
        $price = self::config()['cues'][$id] ?? (int) $meta['price'];
        return ['name' => $meta['name'], 'price' => $price, 'currency' => $meta['currency']];
    }

    public static function boardPrice(string $kind, string $id): int
    {
        $boards = self::config()['boards'];
        if (!isset($boards[$kind][$id])) {
            throw ApiError::notFound('No such board');
        }
        return (int) $boards[$kind][$id];
    }

    /** @return array<string, array<string, int>> */
    public static function boards(): array
    {
        return self::config()['boards'];
    }
}
