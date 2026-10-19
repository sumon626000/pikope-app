<?php
declare(strict_types=1);

namespace App;

/** Admin sign-in: .env ADMIN_USER/PASS, or credentials saved from /admin/account. */
final class AdminAuth
{
    private const KEY = 'admin_auth';
    private const MIN_PASS = 12;

    public static function isEnabled(): bool
    {
        if (self::stored() !== null) {
            return true;
        }
        $user = trim((string) Config::get('ADMIN_USER', ''));
        $pass = (string) Config::get('ADMIN_PASS', '');
        return $user !== '' && $pass !== '';
    }

    public static function username(): string
    {
        $stored = self::stored();
        if ($stored !== null) {
            return $stored['user'];
        }
        return trim((string) Config::get('ADMIN_USER', ''));
    }

    public static function verify(string $user, string $pass): bool
    {
        $stored = self::stored();
        if ($stored !== null) {
            return hash_equals($stored['user'], $user) && password_verify($pass, $stored['passHash']);
        }
        $envUser = trim((string) Config::get('ADMIN_USER', ''));
        $envPass = (string) Config::get('ADMIN_PASS', '');
        return $envUser !== '' && hash_equals($envUser, $user) && hash_equals($envPass, $pass);
    }

    public static function csrfToken(): string
    {
        $user = self::username();
        $secret = self::csrfSecret();
        return hash_hmac('sha256', 'csrf-v2|' . date('Y-m-d') . '|' . $user, $secret);
    }

    /** @var array{user:string,passHash:string,csrfSecret:string,updatedAt:string}|null|false */
    private static array|null|false $storedCache = false;

    /** @return array{user:string,passHash:string,csrfSecret:string,updatedAt:string}|null */
    public static function stored(): ?array
    {
        if (self::$storedCache !== false) {
            return self::$storedCache;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = ?", [self::KEY]);
        if ($row === null) {
            return self::$storedCache = null;
        }
        $raw = json_decode($row['v'], true);
        if (!is_array($raw) || !is_string($raw['user'] ?? null) || !is_string($raw['passHash'] ?? null)) {
            return self::$storedCache = null;
        }
        $secret = (string) ($raw['csrfSecret'] ?? '');
        if ($secret === '') {
            $secret = hash('sha256', 'csrf|' . $raw['passHash']);
        }
        return self::$storedCache = [
            'user' => $raw['user'],
            'passHash' => $raw['passHash'],
            'csrfSecret' => $secret,
            'updatedAt' => (string) ($raw['updatedAt'] ?? ''),
        ];
    }

    public static function usesStoredCredentials(): bool
    {
        return self::stored() !== null;
    }

    /**
     * @throws ApiError
     */
    public static function change(string $currentPass, string $newUser, string $newPass, ?string $confirm = null): void
    {
        $user = self::username();
        if (!self::verify($user, $currentPass)) {
            throw ApiError::badRequest('Current password is wrong');
        }
        $newUser = trim($newUser);
        if ($newUser === '' || strlen($newUser) > 64 || !preg_match('/^[A-Za-z0-9._-]+$/', $newUser)) {
            throw ApiError::badRequest('Username must be 1–64 letters, numbers, dots, underscores or hyphens');
        }
        if (strlen($newPass) < self::MIN_PASS) {
            throw ApiError::badRequest('New password must be at least ' . self::MIN_PASS . ' characters');
        }
        if ($confirm !== null && !hash_equals($newPass, $confirm)) {
            throw ApiError::badRequest('New password and confirmation do not match');
        }
        $payload = [
            'user' => $newUser,
            'passHash' => password_hash($newPass, PASSWORD_DEFAULT),
            'csrfSecret' => bin2hex(random_bytes(32)),
            'updatedAt' => gmdate('c'),
        ];
        Db::run(
            "INSERT INTO settings (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [self::KEY, json_encode($payload)]
        );
        self::$storedCache = false;
    }

    private static function csrfSecret(): string
    {
        $stored = self::stored();
        if ($stored !== null) {
            return $stored['csrfSecret'];
        }
        $user = trim((string) Config::get('ADMIN_USER', ''));
        $pass = (string) Config::get('ADMIN_PASS', '');
        return hash('sha256', 'env-admin-csrf|' . $user . '|' . $pass);
    }
}
