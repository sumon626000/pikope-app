<?php
declare(strict_types=1);

namespace App;

/** Settings from `.env`; real environment variables win over the file. */
final class Config
{
    /** @var array<string,string> */
    private static array $values = [];

    public static function load(string $path): void
    {
        if (is_file($path)) {
            foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
                $line = trim($line);
                if ($line === '' || $line[0] === '#' || !str_contains($line, '=')) {
                    continue;
                }
                [$key, $value] = explode('=', $line, 2);
                self::$values[trim($key)] = trim($value, " \t\"'");
            }
        }
    }

    public static function get(string $key, string $default = ''): string
    {
        $env = getenv($key);
        if ($env !== false && $env !== '') {
            return $env;
        }
        return self::$values[$key] ?? $default;
    }

    public static function int(string $key, int $default): int
    {
        $v = self::get($key);
        return $v === '' ? $default : (int) $v;
    }

    public static function debug(): bool
    {
        return self::get('APP_DEBUG', '0') === '1';
    }
}
