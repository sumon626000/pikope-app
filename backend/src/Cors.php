<?php
declare(strict_types=1);

namespace App;

/** Browser clients (Flutter web) need CORS; mobile APK does not. */
final class Cors
{
    public static function apply(): void
    {
        $configured = trim(Config::get('CORS_ORIGIN', ''));
        if ($configured === '') {
            return;
        }
        $requestOrigin = trim((string) ($_SERVER['HTTP_ORIGIN'] ?? ''));
        $allowed = self::parseOrigins($configured);
        $pick = '';
        if ($requestOrigin !== '' && in_array($requestOrigin, $allowed, true)) {
            $pick = $requestOrigin;
        } elseif (count($allowed) === 1) {
            $pick = $allowed[0];
        }
        if ($pick === '') {
            return;
        }
        header('Access-Control-Allow-Origin: ' . $pick);
        header('Vary: Origin');
        header('Access-Control-Allow-Headers: Authorization, Content-Type');
        header('Access-Control-Allow-Methods: GET, POST, PATCH, OPTIONS');
    }

    /** @return list<string> */
    private static function parseOrigins(string $raw): array
    {
        $parts = preg_split('/\s*,\s*/', $raw) ?: [];
        $out = [];
        foreach ($parts as $p) {
            $p = trim($p);
            if ($p !== '') {
                $out[] = $p;
            }
        }
        return $out;
    }
}
