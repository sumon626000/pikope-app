<?php
declare(strict_types=1);

namespace App;

/** YouTube help videos for shop: add coins, redeem (withdraw), transfer. Edited in admin. */
final class CoinTutorials
{
    /** Demo links — replace in Admin → Coin help videos. */
    public const DEFAULTS = [
        'depositUrl' => 'https://www.youtube.com/watch?v=ysz5Po6i3w8',
        'redeemUrl' => 'https://www.youtube.com/watch?v=jfKfPfyJRdk',
        'transferUrl' => 'https://www.youtube.com/watch?v=5qap5aO4i9A',
    ];

    /** @var array<string,string>|null */
    private static ?array $config = null;

    /** @return array<string,string> */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'coin_tutorials'");
        $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
        $merged = array_merge(self::DEFAULTS, array_intersect_key($saved, self::DEFAULTS));
        self::$config = self::normalize($merged);
        return self::$config;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('coin_tutorials', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode(self::normalize($raw))]
        );
        self::$config = null;
    }

    /** @return array{deposit: string, redeem: string, transfer: string} */
    public static function public(): array
    {
        $c = self::config();
        return [
            'deposit' => $c['depositUrl'],
            'redeem' => $c['redeemUrl'],
            'transfer' => $c['transferUrl'],
        ];
    }

    /** @param array<string,mixed> $raw */
    private static function normalize(array $raw): array
    {
        return [
            'depositUrl' => self::cleanUrl((string) ($raw['depositUrl'] ?? '')),
            'redeemUrl' => self::cleanUrl((string) ($raw['redeemUrl'] ?? '')),
            'transferUrl' => self::cleanUrl((string) ($raw['transferUrl'] ?? '')),
        ];
    }

    private static function cleanUrl(string $url): string
    {
        $url = trim($url);
        if ($url === '') {
            return '';
        }
        if (!preg_match('#^https?://#i', $url)) {
            $url = 'https://' . $url;
        }
        return $url;
    }
}
