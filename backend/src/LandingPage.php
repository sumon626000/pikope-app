<?php
declare(strict_types=1);

namespace App;

/** Public marketing site (pikope.com) — APK, hero image, screenshots, BN/EN copy. */
final class LandingPage
{
    public const MAX_SHOTS = 8;
    private const UPLOAD_DIR = 'uploads/landing';
    private const APK_NAME = 'pikope-latest.apk';
    private const HERO_NAME = 'hero-bg';
    private const ICON_NAME = 'app-icon';

    /** @var array<string,array<string,mixed>> */
    public const LOCALE_DEFAULTS = [
        'bn' => [
            'headline' => 'দক্ষতার গেমিং হাব',
            'tagline' => 'অনলাইন Pool, Ludo ও Carrom — Pico coin অর্জন করুন, বন্ধুদের চ্যালেঞ্জ করুন।',
            'apkLabel' => 'APK ডাউনলোড',
            'features' => [
                'অনলাইন ১ভি১ ও রুম',
                'Pico coin ওয়ালেট ও শপ',
                'ফেয়ার প্লে · দক্ষতার খেলা',
            ],
            'aboutBody' => 'PikoPe একটি দক্ষতা-ভিত্তিক গেমিং অ্যাপ: অনলাইন 8-Ball Pool, Ludo ও Carrom। Pico coin ওয়ালেট, শপ ও ম্যাচ — সব এক জায়গায়। শুধু অফিশিয়াল pikope.com থেকে APK নিন।',
        ],
        'en' => [
            'headline' => 'Skill gaming hub',
            'tagline' => 'Real-skill Pool, Ludo & Carrom — play online, earn Pico coin, challenge friends.',
            'apkLabel' => 'Download APK',
            'features' => [
                'Online 1v1 & rooms',
                'Pico coin wallet & shop',
                'Fair play · skill-based',
            ],
            'aboutBody' => 'PikoPe is a skill-based gaming app: online 8-Ball Pool, Ludo, and Carrom with a Pico coin wallet, shop, and fair competitive matches. Download the official APK only from pikope.com.',
        ],
    ];

    public const DEFAULTS = [
        'enabled' => true,
        'defaultLang' => 'bn',
        'apkUrl' => '',
        'apkFile' => '',
        'heroImage' => '',
        'appIcon' => '',
        'screenshots' => [],
        'statRating' => '4.8',
        'statReviews' => '12K+',
        'statDownloads' => '500K+',
        'statRated' => '18+',
        'updatedLabel' => '',
    ];

    /** @var array<string,mixed>|null */
    private static ?array $config = null;

    /** @return array<string,mixed> */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'landing_page'");
        $saved = $row === null ? [] : (json_decode((string) $row['v'], true) ?: []);
        if (!is_array($saved)) {
            $saved = [];
        }
        $saved = self::migrateLegacy($saved);
        $merged = array_merge(self::DEFAULTS, $saved);
        $merged['bn'] = self::mergeLocale('bn', $saved);
        $merged['en'] = self::mergeLocale('en', $saved);
        self::$config = self::normalize($merged);
        return self::$config;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        $prev = self::config();
        $shots = $prev['screenshots'];
        if (isset($raw['screenshots']) && is_array($raw['screenshots'])) {
            $shots = array_values(array_filter(array_map('strval', $raw['screenshots'])));
            $shots = array_slice($shots, 0, self::MAX_SHOTS);
        }
        $merged = array_merge($prev, $raw, ['screenshots' => $shots]);
        if (isset($raw['bn']) && is_array($raw['bn'])) {
            $merged['bn'] = array_merge($prev['bn'], $raw['bn']);
        }
        if (isset($raw['en']) && is_array($raw['en'])) {
            $merged['en'] = array_merge($prev['en'], $raw['en']);
        }
        $clean = self::normalize($merged);
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('landing_page', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode($clean)]
        );
        self::$config = null;
    }

    /** JSON for pikope.com (all locales; site defaults to BN). */
    public static function publicPayload(): array
    {
        $c = self::config();
        $base = rtrim(Config::get('APP_URL', ''), '/');
        $apk = self::resolveApkUrl($c, $base);
        $shots = self::publicUrls($c['screenshots'], $base);
        $hero = self::publicUrl((string) $c['heroImage'], $base);
        $icon = self::publicUrl((string) $c['appIcon'], $base);
        $defaultLang = (string) $c['defaultLang'];
        if (!isset(self::LOCALE_DEFAULTS[$defaultLang])) {
            $defaultLang = 'bn';
        }
        return [
            'enabled' => (bool) $c['enabled'],
            'brand' => 'PikoPe',
            'defaultLang' => $defaultLang,
            'apkUrl' => $apk,
            'heroImageUrl' => $hero,
            'appIconUrl' => $icon,
            'screenshots' => $shots,
            'locales' => [
                'bn' => self::localeOut($c['bn']),
                'en' => self::localeOut($c['en']),
            ],
            'stats' => [
                'rating' => (string) $c['statRating'],
                'reviews' => (string) $c['statReviews'],
                'downloads' => (string) $c['statDownloads'],
                'rated' => (string) $c['statRated'],
            ],
            'updatedLabel' => (string) $c['updatedLabel'],
            'apiBase' => $base,
            'support' => SupportLinks::config(),
        ];
    }

    /** @param array<string,mixed> $file from $_FILES */
    public static function storeScreenshot(array $file): string
    {
        return self::storeImage($file, 'shot');
    }

    /** @param array<string,mixed> $file from $_FILES */
    public static function storeHeroImage(array $file): string
    {
        $c = self::config();
        if ((string) $c['heroImage'] !== '') {
            self::removeStoredFile((string) $c['heroImage']);
        }
        $rel = self::storeImage($file, self::HERO_NAME);
        return $rel;
    }

    /** @param array<string,mixed> $file from $_FILES — same artwork as Play Store / APK icon (square). */
    public static function storeAppIcon(array $file): string
    {
        $c = self::config();
        if ((string) $c['appIcon'] !== '') {
            self::removeStoredFile((string) $c['appIcon']);
        }
        return self::storeImage($file, self::ICON_NAME);
    }

    /** @param array<string,mixed> $file from $_FILES */
    public static function storeApk(array $file): string
    {
        if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            throw ApiError::badRequest('APK upload failed.', 'upload');
        }
        $size = (int) ($file['size'] ?? 0);
        if ($size < 1 || $size > 160 * 1024 * 1024) {
            throw ApiError::badRequest('APK must be under 160 MB.', 'upload');
        }
        $name = (string) ($file['name'] ?? '');
        if (!str_ends_with(strtolower($name), '.apk')) {
            throw ApiError::badRequest('File must be .apk', 'upload');
        }
        $finfo = new \finfo(FILEINFO_MIME_TYPE);
        $mime = $finfo->file((string) $file['tmp_name']);
        $ok = in_array($mime, [
            'application/vnd.android.package-archive',
            'application/octet-stream',
            'application/zip',
        ], true);
        if (!$ok) {
            throw ApiError::badRequest('Invalid APK file type.', 'upload');
        }
        $dir = dirname(__DIR__) . '/public/' . self::UPLOAD_DIR;
        if (!is_dir($dir) && !mkdir($dir, 0755, true) && !is_dir($dir)) {
            throw ApiError::badRequest('Could not create upload folder.', 'upload');
        }
        $c = self::config();
        if ((string) $c['apkFile'] !== '') {
            self::removeStoredFile((string) $c['apkFile']);
        }
        $dest = $dir . '/' . self::APK_NAME;
        if (!move_uploaded_file((string) $file['tmp_name'], $dest)) {
            throw ApiError::badRequest('Could not save APK.', 'upload');
        }
        return self::UPLOAD_DIR . '/' . self::APK_NAME;
    }

    public static function removeScreenshot(string $rel): void
    {
        self::removeStoredFile($rel);
    }

    public static function clearApkFile(): void
    {
        $c = self::config();
        if ((string) $c['apkFile'] !== '') {
            self::removeStoredFile((string) $c['apkFile']);
        }
        self::save(['apkFile' => '']);
    }

    public static function clearHeroImage(): void
    {
        $c = self::config();
        if ((string) $c['heroImage'] !== '') {
            self::removeStoredFile((string) $c['heroImage']);
        }
        self::save(['heroImage' => '']);
    }

    public static function clearAppIcon(): void
    {
        $c = self::config();
        if ((string) $c['appIcon'] !== '') {
            self::removeStoredFile((string) $c['appIcon']);
        }
        self::save(['appIcon' => '']);
    }

    /** @param array<string,mixed> $file @param non-empty-string $prefix */
    private static function storeImage(array $file, string $prefix): string
    {
        if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            throw ApiError::badRequest('Upload failed.', 'upload');
        }
        $max = $prefix === self::HERO_NAME ? 5 * 1024 * 1024 : 3 * 1024 * 1024;
        if ((int) ($file['size'] ?? 0) > $max) {
            throw ApiError::badRequest('Image too large.', 'upload');
        }
        $finfo = new \finfo(FILEINFO_MIME_TYPE);
        $mime = $finfo->file((string) $file['tmp_name']);
        $ext = match ($mime) {
            'image/jpeg' => 'jpg',
            'image/png' => 'png',
            'image/webp' => 'webp',
            default => throw ApiError::badRequest('Use JPG, PNG or WebP.', 'upload'),
        };
        $dir = dirname(__DIR__) . '/public/' . self::UPLOAD_DIR;
        if (!is_dir($dir) && !mkdir($dir, 0755, true) && !is_dir($dir)) {
            throw ApiError::badRequest('Could not create upload folder.', 'upload');
        }
        $name = match ($prefix) {
            'shot' => bin2hex(random_bytes(8)) . '.' . $ext,
            self::HERO_NAME => self::HERO_NAME . '.' . $ext,
            self::ICON_NAME => self::ICON_NAME . '.' . $ext,
            default => bin2hex(random_bytes(8)) . '.' . $ext,
        };
        if (!move_uploaded_file((string) $file['tmp_name'], $dir . '/' . $name)) {
            throw ApiError::badRequest('Could not save image.', 'upload');
        }
        return self::UPLOAD_DIR . '/' . $name;
    }

    private static function removeStoredFile(string $rel): void
    {
        $rel = ltrim(str_replace('\\', '/', $rel), '/');
        if ($rel === '' || str_contains($rel, '..') || !str_starts_with($rel, self::UPLOAD_DIR . '/')) {
            return;
        }
        $path = dirname(__DIR__) . '/public/' . $rel;
        if (is_file($path)) {
            @unlink($path);
        }
    }

    /** Landing upload or optional landing URL — same file pikope.com download uses. */
    public static function liveApkDownloadUrl(): string
    {
        $c = self::config();
        $base = rtrim(Config::get('APP_URL', ''), '/');
        $file = trim((string) $c['apkFile']);
        if ($file !== '') {
            return self::publicUrl($file, $base);
        }
        return trim((string) $c['apkUrl']);
    }

    /** @param array<string,mixed> $c */
    private static function resolveApkUrl(array $c, string $base): string
    {
        unset($c, $base);
        $apk = self::liveApkDownloadUrl();
        if ($apk !== '') {
            return $apk;
        }
        return trim((string) (AppUpdate::config()['apkUrl'] ?? ''));
    }

    /** @param list<string> $rels */
    private static function publicUrls(array $rels, string $base): array
    {
        $out = [];
        foreach ($rels as $rel) {
            $u = self::publicUrl((string) $rel, $base);
            if ($u !== '') {
                $out[] = $u;
            }
        }
        return $out;
    }

    private static function publicUrl(string $rel, string $base): string
    {
        $rel = ltrim(str_replace('\\', '/', $rel), '/');
        if ($rel === '' || str_contains($rel, '..')) {
            return '';
        }
        return $base === '' ? '/' . $rel : $base . '/' . $rel;
    }

    /** @param array<string,mixed> $loc @return array<string,mixed> */
    private static function localeOut(array $loc): array
    {
        return [
            'headline' => (string) $loc['headline'],
            'tagline' => (string) $loc['tagline'],
            'apkLabel' => (string) $loc['apkLabel'],
            'aboutBody' => (string) $loc['aboutBody'],
            'features' => array_values($loc['features']),
        ];
    }

    /** @param array<string,mixed> $saved @return array<string,mixed> */
    private static function migrateLegacy(array $saved): array
    {
        if (isset($saved['bn']) || !isset($saved['headline'])) {
            return $saved;
        }
        $legacy = [
            'headline' => $saved['headline'] ?? '',
            'tagline' => $saved['tagline'] ?? '',
            'apkLabel' => $saved['apkLabel'] ?? '',
            'features' => $saved['features'] ?? [],
        ];
        $saved['en'] = array_merge(self::LOCALE_DEFAULTS['en'], array_filter($legacy));
        $saved['bn'] = self::LOCALE_DEFAULTS['bn'];
        unset($saved['headline'], $saved['tagline'], $saved['apkLabel'], $saved['features']);
        return $saved;
    }

    /** @param array<string,mixed> $saved @return array<string,mixed> */
    private static function mergeLocale(string $lang, array $saved): array
    {
        $def = self::LOCALE_DEFAULTS[$lang];
        $block = $saved[$lang] ?? [];
        if (!is_array($block)) {
            $block = [];
        }
        return array_merge($def, $block);
    }

    /** @param array<string,mixed> $raw @return array<string,mixed> */
    private static function normalize(array $raw): array
    {
        $defaultLang = strtolower(trim((string) ($raw['defaultLang'] ?? 'bn')));
        if (!isset(self::LOCALE_DEFAULTS[$defaultLang])) {
            $defaultLang = 'bn';
        }

        $shots = $raw['screenshots'] ?? [];
        if (!is_array($shots)) {
            $shots = [];
        }
        $shots = array_slice(array_values(array_filter(array_map('strval', $shots))), 0, self::MAX_SHOTS);

        $apk = trim((string) ($raw['apkUrl'] ?? ''));
        if ($apk !== '' && (strlen($apk) > 400 || !preg_match('#^https://#i', $apk))) {
            throw ApiError::badRequest('APK link must be https://', 'bad_link');
        }

        $apkFile = trim((string) ($raw['apkFile'] ?? ''));
        if ($apkFile !== '' && !str_starts_with($apkFile, self::UPLOAD_DIR . '/')) {
            throw ApiError::badRequest('Invalid APK path.', 'bad_path');
        }

        $hero = trim((string) ($raw['heroImage'] ?? ''));
        if ($hero !== '' && !str_starts_with($hero, self::UPLOAD_DIR . '/')) {
            throw ApiError::badRequest('Invalid hero image path.', 'bad_path');
        }

        $appIcon = trim((string) ($raw['appIcon'] ?? ''));
        if ($appIcon !== '' && !str_starts_with($appIcon, self::UPLOAD_DIR . '/')) {
            throw ApiError::badRequest('Invalid app icon path.', 'bad_path');
        }

        return [
            'enabled' => (bool) ($raw['enabled'] ?? true),
            'defaultLang' => $defaultLang,
            'apkUrl' => $apk,
            'apkFile' => $apkFile,
            'heroImage' => $hero,
            'appIcon' => $appIcon,
            'screenshots' => $shots,
            'statRating' => mb_substr(trim((string) ($raw['statRating'] ?? self::DEFAULTS['statRating'])), 0, 8),
            'statReviews' => mb_substr(trim((string) ($raw['statReviews'] ?? self::DEFAULTS['statReviews'])), 0, 16),
            'statDownloads' => mb_substr(trim((string) ($raw['statDownloads'] ?? self::DEFAULTS['statDownloads'])), 0, 16),
            'statRated' => mb_substr(trim((string) ($raw['statRated'] ?? self::DEFAULTS['statRated'])), 0, 12),
            'updatedLabel' => mb_substr(trim((string) ($raw['updatedLabel'] ?? '')), 0, 40),
            'bn' => self::normalizeLocale($raw['bn'] ?? [], 'bn'),
            'en' => self::normalizeLocale($raw['en'] ?? [], 'en'),
        ];
    }

    /** @param array<string,mixed> $raw @return array<string,mixed> */
    private static function normalizeLocale(array $raw, string $lang): array
    {
        $def = self::LOCALE_DEFAULTS[$lang];
        $features = $raw['features'] ?? $def['features'];
        if (!is_array($features)) {
            $features = $def['features'];
        }
        $features = array_values(array_filter(array_map(
            static fn ($x): string => mb_substr(trim((string) $x), 0, 80),
            $features
        )));
        if ($features === []) {
            $features = $def['features'];
        }
        $features = array_slice($features, 0, 6);

        $about = trim((string) ($raw['aboutBody'] ?? $def['aboutBody'] ?? ''));
        if ($about === '') {
            $about = (string) $def['aboutBody'];
        }

        return [
            'headline' => mb_substr(trim((string) ($raw['headline'] ?? $def['headline'])), 0, 60) ?: $def['headline'],
            'tagline' => mb_substr(trim((string) ($raw['tagline'] ?? $def['tagline'])), 0, 220) ?: $def['tagline'],
            'apkLabel' => mb_substr(trim((string) ($raw['apkLabel'] ?? $def['apkLabel'])), 0, 40) ?: $def['apkLabel'],
            'aboutBody' => mb_substr($about, 0, 600),
            'features' => $features,
        ];
    }
}
