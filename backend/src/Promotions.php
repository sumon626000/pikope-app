<?php
declare(strict_types=1);

namespace App;

/** Time-limited deposit and win bonuses (e.g. double Pico coin on add / double match prize). */
final class Promotions
{
    public const DEFAULTS = [
        'depositBonusEnabled' => false,
        'depositBonusPercent' => 100,
        'depositEndsAt' => '',
        'winBonusEnabled' => false,
        'winBonusPercent' => 100,
        'winEndsAt' => '',
        'title' => 'Double deposit · Double win',
    ];

    /** @var array<string,mixed>|null */
    private static ?array $config = null;

    /** @return array<string,mixed> */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'promotions'");
        $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
        self::$config = self::normalize(array_merge(self::DEFAULTS, array_intersect_key($saved, self::DEFAULTS)));
        return self::$config;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('promotions', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode(self::normalize($raw))]
        );
        self::$config = null;
    }

    /** Fingerprint of the live offer (empty when no bonus is active right now). */
    public static function liveOfferSignature(): string
    {
        $c = self::config();
        $bits = [];
        if (self::depositBonusActive()) {
            $bits[] = 'd' . (int) $c['depositBonusPercent'] . '@' . (string) $c['depositEndsAt'];
        }
        if (self::winBonusActive()) {
            $bits[] = 'w' . (int) $c['winBonusPercent'] . '@' . (string) $c['winEndsAt'];
        }
        if ($bits === []) {
            return '';
        }
        return implode(';', $bits) . ';t=' . trim((string) $c['title']);
    }

    /** @return array{title:string,body:string} */
    public static function pushCopy(): array
    {
        $c = self::config();
        $title = trim((string) $c['title']);
        if ($title === '') {
            $title = 'New offer';
        }
        $lines = [];
        if (self::depositBonusActive()) {
            $pct = (int) $c['depositBonusPercent'];
            $lines[] = $pct > 0
                ? "Add coin: +{$pct}% extra Pico on approved deposits."
                : 'Add coin bonus is live.';
        }
        if (self::winBonusActive()) {
            $pct = (int) $c['winBonusPercent'];
            $lines[] = $pct > 0
                ? "Win matches: +{$pct}% extra on your prize."
                : 'Win bonus is live.';
        }
        $body = $lines === [] ? 'Check the app for current promotions.' : implode(' ', $lines);
        $ends = self::offerEndHint();
        if ($ends !== '') {
            $body = mb_substr($body . ' ' . $ends, 0, 500);
        }
        return ['title' => mb_substr($title, 0, 80), 'body' => mb_substr($body, 0, 500)];
    }

    /**
     * When a live offer starts or changes, notify all players (inbox + FCM).
     *
     * @return array{sent:int,failed:int,inbox:int}|null
     */
    public static function broadcastPushIfOfferChanged(string $beforeSignature): ?array
    {
        $after = self::liveOfferSignature();
        if ($after === '' || $after === $beforeSignature) {
            return null;
        }
        $copy = self::pushCopy();
        return Push::broadcast($copy['title'], $copy['body']);
    }

    private static function offerEndHint(): string
    {
        $c = self::config();
        $ends = [];
        if (self::depositBonusActive() && trim((string) $c['depositEndsAt']) !== '') {
            $ends[] = strtotime((string) $c['depositEndsAt']) ?: null;
        }
        if (self::winBonusActive() && trim((string) $c['winEndsAt']) !== '') {
            $ends[] = strtotime((string) $c['winEndsAt']) ?: null;
        }
        $ends = array_values(array_filter($ends, static fn ($t): bool => $t !== null));
        if ($ends === []) {
            return '';
        }
        $ts = min($ends);
        return 'Offer ends ' . date('M j, g:i A', $ts) . '.';
    }

    /** @return array{title:string,deposit:?array{bonusPercent:int},win:?array{bonusPercent:int}} */
    public static function publicConfig(): array
    {
        $c = self::config();
        $title = trim((string) $c['title']);
        if ($title === '') {
            $title = 'Promo';
        }
        $dep = self::depositBonusActive() ? ['bonusPercent' => (int) $c['depositBonusPercent']] : null;
        $win = self::winBonusActive() ? ['bonusPercent' => (int) $c['winBonusPercent']] : null;
        return ['title' => $title, 'deposit' => $dep, 'win' => $win];
    }

    public static function depositBonusActive(): bool
    {
        $c = self::config();
        if (!(bool) $c['depositBonusEnabled']) {
            return false;
        }
        return self::beforeEnd((string) $c['depositEndsAt']);
    }

    public static function winBonusActive(): bool
    {
        $c = self::config();
        if (!(bool) $c['winBonusEnabled']) {
            return false;
        }
        return self::beforeEnd((string) $c['winEndsAt']);
    }

    /** Extra % on top of base coins from BDT × rate (100 = double total). */
    public static function depositCoins(int $bdt, int $coinPerBdt): int
    {
        $base = $bdt * max(1, $coinPerBdt);
        if (!self::depositBonusActive()) {
            return $base;
        }
        $pct = max(0, min(500, (int) self::config()['depositBonusPercent']));
        return $base + intdiv($base * $pct, 100);
    }

    /** Match prize paid to winner (100% bonus = double the room prize). */
    public static function prizeWithBonus(int $basePrize): int
    {
        if ($basePrize <= 0 || !self::winBonusActive()) {
            return $basePrize;
        }
        $pct = max(0, min(500, (int) self::config()['winBonusPercent']));
        return $basePrize + intdiv($basePrize * $pct, 100);
    }

    private static function normalizeEndsAt(string $raw): string
    {
        $raw = trim(str_replace('T', ' ', $raw));
        if ($raw === '') {
            return '';
        }
        $ts = strtotime($raw);
        if ($ts === false) {
            return '';
        }
        return date('Y-m-d H:i:s', $ts);
    }

    private static function beforeEnd(string $endsAt): bool
    {
        $endsAt = trim($endsAt);
        if ($endsAt === '') {
            return true;
        }
        $ts = strtotime($endsAt);
        if ($ts === false) {
            return true;
        }
        return time() <= $ts;
    }

    /** @param array<string,mixed> $raw */
    private static function normalize(array $raw): array
    {
        return [
            'depositBonusEnabled' => (bool) ($raw['depositBonusEnabled'] ?? false),
            'depositBonusPercent' => max(0, min(500, (int) ($raw['depositBonusPercent'] ?? 100))),
            'depositEndsAt' => self::normalizeEndsAt((string) ($raw['depositEndsAt'] ?? '')),
            'winBonusEnabled' => (bool) ($raw['winBonusEnabled'] ?? false),
            'winBonusPercent' => max(0, min(500, (int) ($raw['winBonusPercent'] ?? 100))),
            'winEndsAt' => self::normalizeEndsAt((string) ($raw['winEndsAt'] ?? '')),
            'title' => mb_substr(trim((string) ($raw['title'] ?? self::DEFAULTS['title'])), 0, 80),
        ];
    }
}
