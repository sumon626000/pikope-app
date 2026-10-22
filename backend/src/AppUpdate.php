<?php
declare(strict_types=1);

namespace App;

/** Newest APK the installed app may download and open the installer for. */
final class AppUpdate
{
    public const DEFAULTS = [
        'enabled' => false,
        'versionCode' => 0,
        'versionName' => '',
        'apkUrl' => '',
        'apkSha256' => '',
        'notes' => '',
        'required' => false,
    ];

    /** @var array<string,mixed>|null */
    private static ?array $config = null;

    /** @return array<string,mixed> */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'app_update'");
        $saved = $row === null ? [] : (json_decode((string) $row['v'], true) ?: []);
        self::$config = self::normalize(is_array($saved) ? $saved : []);
        return self::$config;
    }

    /** What the app is allowed to see. Disabled or incomplete settings publish nothing. */
    public static function published(): array
    {
        $c = self::config();
        $apkUrl = trim((string) $c['apkUrl']);
        if ($apkUrl === '') {
            $apkUrl = LandingPage::liveApkDownloadUrl();
        }
        if (!$c['enabled'] || $apkUrl === '' || (int) $c['versionCode'] < 1) {
            return [
                'versionCode' => 0,
                'versionName' => '',
                'apkUrl' => '',
                'notes' => '',
                'required' => false,
            ];
        }
        $out = [
            'versionCode' => (int) $c['versionCode'],
            'versionName' => $c['versionName'],
            'apkUrl' => $apkUrl,
            'notes' => $c['notes'],
            'required' => (bool) $c['required'],
        ];
        if ($c['apkSha256'] !== '') {
            $out['apkSha256'] = $c['apkSha256'];
        }
        return $out;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        $clean = self::normalize($raw);
        $apkEffective = $clean['apkUrl'] !== '' ? $clean['apkUrl'] : LandingPage::liveApkDownloadUrl();
        if ($clean['enabled'] && ($clean['versionCode'] < 1 || $apkEffective === '')) {
            throw ApiError::badRequest('Set a version code and upload the landing APK (or paste an APK link) before turning the update on', 'bad_update');
        }
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('app_update', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode($clean)]
        );
        self::$config = $clean;
    }

    /** @param array<string,mixed> $raw @return array<string,mixed> */
    private static function normalize(array $raw): array
    {
        $name = trim((string) ($raw['versionName'] ?? ''));
        $notes = trim((string) ($raw['notes'] ?? ''));
        if (strlen($name) > 40) {
            $name = substr($name, 0, 40);
        }
        if (strlen($notes) > 400) {
            $notes = substr($notes, 0, 400);
        }
        $sha = strtolower(preg_replace('/\s+/', '', trim((string) ($raw['apkSha256'] ?? ''))) ?? '');
        if ($sha !== '' && preg_match('/^[a-f0-9]{64}$/', $sha) !== 1) {
            throw ApiError::badRequest('APK SHA-256 must be 64 hex characters or left empty', 'bad_hash');
        }
        return [
            'enabled' => filter_var($raw['enabled'] ?? false, FILTER_VALIDATE_BOOLEAN),
            'versionCode' => max(0, (int) ($raw['versionCode'] ?? 0)),
            'versionName' => $name,
            'apkUrl' => self::url($raw['apkUrl'] ?? ''),
            'apkSha256' => $sha,
            'notes' => $notes,
            'required' => filter_var($raw['required'] ?? false, FILTER_VALIDATE_BOOLEAN),
        ];
    }

    private static function url(mixed $raw): string
    {
        $url = trim((string) $raw);
        if ($url === '') {
            return '';
        }
        if (strlen($url) > 400 || !preg_match('#^https://#i', $url) || str_contains($url, ' ')) {
            throw ApiError::badRequest('The APK link must start with https://', 'bad_link');
        }
        $host = strtolower((string) (parse_url($url, PHP_URL_HOST) ?: ''));
        if ($host === '') {
            throw ApiError::badRequest('The APK link must start with https://', 'bad_link');
        }
        $appHost = strtolower((string) (parse_url(trim(Config::get('APP_URL')), PHP_URL_HOST) ?: ''));
        if ($appHost !== '' && $host !== $appHost) {
            throw ApiError::badRequest('The APK link must use the same host as APP_URL', 'bad_link');
        }
        return $url;
    }
}
