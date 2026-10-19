<?php
declare(strict_types=1);

namespace App;

/** Request parsing and JSON responses. */
final class Http
{
    /** @var array<string,mixed>|null */
    private static ?array $body = null;

    public static function method(): string
    {
        return strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
    }

    public static function path(): string
    {
        $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
        // Allow the API to live in a sub-directory (e.g. /api).
        $base = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
        if ($base !== '' && str_starts_with($path, $base)) {
            $path = substr($path, strlen($base));
        }
        if (str_starts_with($path, '/index.php')) {
            $path = substr($path, strlen('/index.php'));
        }
        return '/' . trim($path, '/');
    }

    /** @return array<string,mixed> */
    public static function body(): array
    {
        if (self::$body === null) {
            $raw = file_get_contents('php://input') ?: '';
            $data = $raw === '' ? [] : json_decode($raw, true);
            if (!is_array($data)) {
                throw ApiError::badRequest('Body must be a JSON object');
            }
            self::$body = $data;
        }
        return self::$body;
    }

    public static function str(string $key, int $max = 255, bool $required = true): string
    {
        $v = self::body()[$key] ?? null;
        if ($v === null || $v === '') {
            if ($required) {
                throw ApiError::badRequest("'$key' is required");
            }
            return '';
        }
        if (!is_string($v) || mb_strlen($v) > $max) {
            throw ApiError::badRequest("'$key' is invalid");
        }
        return trim($v);
    }

    /** HTTP Basic credentials (Hostinger/CGI often omit PHP_AUTH_*). */
    public static function basicAuth(): array
    {
        $user = (string) ($_SERVER['PHP_AUTH_USER'] ?? '');
        $pass = (string) ($_SERVER['PHP_AUTH_PW'] ?? '');
        if ($user !== '' || $pass !== '') {
            return [$user, $pass];
        }
        $header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
        if ($header === '' && function_exists('getallheaders')) {
            foreach (getallheaders() as $name => $value) {
                if (strcasecmp((string) $name, 'Authorization') === 0) {
                    $header = (string) $value;
                }
            }
        }
        if (preg_match('/^Basic\s+(\S+)$/i', $header, $m)) {
            $decoded = base64_decode($m[1], true);
            if ($decoded !== false && str_contains($decoded, ':')) {
                return explode(':', $decoded, 2);
            }
        }
        return ['', ''];
    }

    public static function bearer(): ?string
    {
        $header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
        if ($header === '' && function_exists('getallheaders')) {
            foreach (getallheaders() as $name => $value) {
                if (strcasecmp($name, 'Authorization') === 0) {
                    $header = $value;
                }
            }
        }
        return preg_match('/^Bearer\s+(\S+)$/i', $header, $m) ? $m[1] : null;
    }

    public static function json(mixed $data, int $status = 200): never
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }
}
