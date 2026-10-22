<?php
declare(strict_types=1);

namespace App;

/** Facebook and Telegram support links shown in the app settings. */
final class SupportLinks
{
    public const DEFAULTS = [
        'facebook' => '',
        'telegram' => '',
    ];

    /** @var array{facebook:string,telegram:string}|null */
    private static ?array $config = null;

    /** @return array{facebook:string,telegram:string} */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'support'");
        $saved = $row === null ? [] : (json_decode((string) $row['v'], true) ?: []);
        self::$config = self::normalize(is_array($saved) ? $saved : []);
        return self::$config;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        $clean = self::normalize($raw);
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('support', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode($clean)]
        );
        self::$config = $clean;
    }

    /** @param array<string,mixed> $raw @return array{facebook:string,telegram:string} */
    private static function normalize(array $raw): array
    {
        return [
            'facebook' => self::url($raw['facebook'] ?? ''),
            'telegram' => self::url($raw['telegram'] ?? ''),
        ];
    }

    private static function url(mixed $raw): string
    {
        $url = trim((string) $raw);
        if ($url === '') {
            return '';
        }
        if (strlen($url) > 300) {
            throw ApiError::badRequest('Link is too long', 'bad_link');
        }
        if (!preg_match('#^https?://#i', $url)) {
            $url = 'https://' . ltrim($url, '/');
        }
        $parts = parse_url($url);
        $scheme = strtolower((string) ($parts['scheme'] ?? ''));
        $host = strtolower((string) ($parts['host'] ?? ''));
        if (!in_array($scheme, ['http', 'https'], true) || $host === '' || str_contains($url, ' ')) {
            throw ApiError::badRequest('Use a full http or https link', 'bad_link');
        }
        return $url;
    }
}
