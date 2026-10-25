<?php
declare(strict_types=1);

namespace App;

/**
 * APK push (FCM) + in-app notification inbox. FCM server key lives in .env
 * as FCM_SERVER_KEY; event toggles are stored in settings (push).
 */
final class Push
{
    public const KINDS = [
        'deposit_approved',
        'deposit_ok',
        'deposit_rejected',
        'redeem_approved',
        'redeem_rejected',
        'redeem_cancelled',
        'coin_received',
        'coin_sent',
        'wallet',
        'challenge',
        'admin_broadcast',
    ];

    public const DEFAULTS = [
        'enabled' => true,
        'depositApproved' => true,
        'depositRejected' => true,
        'redeemApproved' => true,
        'redeemRejected' => true,
        'coinTransfer' => true,
        'walletActivity' => true,
        'challenge' => true,
        'adminBroadcast' => true,
        'channelId' => 'pikope_default',
        'channelName' => 'PikoPe',
    ];

    /** @var array<string,mixed>|null */
    private static ?array $config = null;

    /** @return array<string,mixed> */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'push'");
        $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
        self::$config = self::normalize(array_merge(self::DEFAULTS, array_intersect_key($saved, self::DEFAULTS)));
        return self::$config;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('push', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode(self::normalize($raw))]
        );
        self::$config = null;
    }

    public static function fcmConfigured(): bool
    {
        return trim(Config::get('FCM_SERVER_KEY', '')) !== '';
    }

    /** @return array{enabled:bool,fcm:bool,tokens:int,unread:int} */
    public static function adminStats(): array
    {
        return [
            'enabled' => (bool) self::config()['enabled'],
            'fcm' => self::fcmConfigured(),
            'tokens' => self::n('SELECT COUNT(*) AS n FROM push_tokens'),
            'devices' => self::n('SELECT COUNT(DISTINCT user_id) AS n FROM push_tokens'),
        ];
    }

    public static function registerToken(int $userId, string $token, string $platform = 'android'): void
    {
        $token = trim($token);
        if ($token === '' || strlen($token) > 512) {
            throw ApiError::badRequest('Invalid device token.', 'bad_push_token');
        }
        $platform = strtolower($platform);
        if (!in_array($platform, ['android', 'ios', 'web'], true)) {
            $platform = 'android';
        }
        Db::run('DELETE FROM push_tokens WHERE token = ? AND user_id <> ?', [$token, $userId]);
        Db::run(
            'INSERT INTO push_tokens (user_id, token, platform) VALUES (?, ?, ?)
             ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), platform = VALUES(platform), updated_at = NOW()',
            [$userId, $token, $platform]
        );
    }

    public static function removeToken(int $userId, string $token): void
    {
        Db::run('DELETE FROM push_tokens WHERE user_id = ? AND token = ?', [$userId, trim($token)]);
    }

    public static function notifyUser(
        int $userId,
        string $kind,
        string $title,
        string $body,
        array $data = [],
        ?string $eventKey = null
    ): void {
        if (!self::deliveryEnabled($kind)) {
            return;
        }
        if ($kind === 'challenge') {
            Auth::ensureChallengesEnabledColumn();
            Auth::ensureChallengeGameColumns();
            $row = Db::one(
                'SELECT challenges_enabled, challenge_pool, challenge_ludo, challenge_carrom FROM users WHERE id = ?',
                [$userId]
            );
            $game = (string) ($data['game'] ?? '');
            if ($row === null || !ChallengeService::userAcceptsGame($row, $game !== '' ? $game : 'billiard')) {
                return;
            }
        }
        $title = mb_substr(trim($title), 0, 80);
        $body = mb_substr(trim($body), 0, 500);
        if ($title === '' || $body === '') {
            return;
        }
        if ($eventKey !== null) {
            $eventKey = mb_substr(trim($eventKey), 0, 80);
            if ($eventKey === '') {
                $eventKey = null;
            }
        }
        if ($eventKey !== null && self::eventAlreadyNotified($userId, $eventKey)) {
            return;
        }
        self::insertInbox($userId, $kind, $title, $body, $eventKey);
        self::sendFcmToUser($userId, $title, $body, $data + ['kind' => $kind] + ($eventKey !== null ? ['eventKey' => $eventKey] : []));
    }

    /** Wallet ledger hook — one push per wallet_tx row (deduped by tx id). */
    public static function notifyWalletChange(int $userId, int $amount, string $reason, ?int $roomId, ?int $walletTxId = null): void
    {
        if (!self::deliveryEnabled('wallet')) {
            return;
        }
        if ($amount === 0) {
            return;
        }
        if (self::walletReasonSkipped($reason)) {
            return;
        }
        $parsed = self::walletMessage($amount, $reason, $roomId);
        if ($parsed === null) {
            return;
        }
        $eventKey = $walletTxId !== null && $walletTxId > 0
            ? 'wallet:tx:' . $walletTxId
            : 'wallet:' . $reason . ':' . time();
        self::notifyUser($userId, 'wallet', $parsed['title'], $parsed['body'], [], $eventKey);
    }

    /** @return array{sent:int,failed:int,inbox:int} */
    public static function broadcast(string $title, string $body): array
    {
        if (!self::deliveryEnabled('admin_broadcast')) {
            return ['sent' => 0, 'failed' => 0, 'inbox' => 0];
        }
        $title = mb_substr(trim($title), 0, 80);
        $body = mb_substr(trim($body), 0, 500);
        if ($title === '' || $body === '') {
            throw ApiError::badRequest('Title and body are required.');
        }
        $users = Db::all('SELECT id FROM users WHERE is_bot = 0 AND banned = 0');
        $inbox = 0;
        $stamp = date('YmdHis');
        foreach ($users as $u) {
            $uid = (int) $u['id'];
            $key = 'broadcast:' . $stamp . ':' . $uid;
            if (self::eventAlreadyNotified($uid, $key)) {
                continue;
            }
            self::insertInbox($uid, 'admin_broadcast', $title, $body, $key);
            $inbox++;
        }
        $tokens = Db::all('SELECT token FROM push_tokens');
        $list = array_column($tokens, 'token');
        $result = self::sendFcmMulticast($list, $title, $body, ['kind' => 'admin_broadcast']);
        return ['sent' => $result['sent'], 'failed' => $result['failed'], 'inbox' => $inbox];
    }

    /** @return array{sent:int,failed:int} */
    public static function sendTest(int $userId, string $title, string $body): array
    {
        self::notifyUser($userId, 'admin_broadcast', $title, $body, ['test' => '1'], 'test:' . $userId . ':' . time());
        $tokens = Db::all('SELECT token FROM push_tokens WHERE user_id = ?', [$userId]);
        if ($tokens === []) {
            return ['sent' => 0, 'failed' => 0];
        }
        return ['sent' => count($tokens), 'failed' => 0];
    }

    /** @return list<array<string,mixed>> */
    public static function inbox(int $userId, int $limit = 40, ?int $afterId = null): array
    {
        $limit = max(1, min(100, $limit));
        $params = [$userId];
        $extra = '';
        if ($afterId !== null && $afterId > 0) {
            $extra = ' AND id > ?';
            $params[] = $afterId;
        }
        $params[] = $limit;
        return Db::all(
            "SELECT id, kind, title, body, read_at, UNIX_TIMESTAMP(created_at) AS at
             FROM user_notifications WHERE user_id = ? $extra
             ORDER BY id DESC LIMIT ?",
            $params
        );
    }

    public static function unreadCount(int $userId): int
    {
        return self::n('SELECT COUNT(*) AS n FROM user_notifications WHERE user_id = ? AND read_at IS NULL', [$userId]);
    }

    public static function markRead(int $userId, ?int $id = null): void
    {
        if ($id !== null && $id > 0) {
            Db::run('UPDATE user_notifications SET read_at = NOW() WHERE user_id = ? AND id = ? AND read_at IS NULL', [$userId, $id]);
            return;
        }
        Db::run('UPDATE user_notifications SET read_at = NOW() WHERE user_id = ? AND read_at IS NULL', [$userId]);
    }

    private static function deliveryEnabled(string $kind): bool
    {
        $c = self::config();
        if (!(bool) $c['enabled']) {
            return false;
        }
        return match ($kind) {
            'deposit_approved', 'deposit_ok' => (bool) $c['depositApproved'],
            'deposit_rejected' => (bool) $c['depositRejected'],
            'redeem_approved', 'redeem_cancelled' => (bool) $c['redeemApproved'],
            'redeem_rejected' => (bool) $c['redeemRejected'],
            'coin_received', 'coin_sent' => (bool) $c['coinTransfer'],
            'wallet' => (bool) $c['walletActivity'],
            'challenge' => (bool) $c['challenge'],
            'admin_broadcast' => (bool) $c['adminBroadcast'],
            default => true,
        };
    }

    private static function walletReasonSkipped(string $reason): bool
    {
        foreach (['deposit:', 'zinipay:', 'transfer_out', 'transfer_in', 'redeem_refund:', 'welcome', 'daily'] as $skip) {
            if ($reason === $skip || str_starts_with($reason, $skip)) {
                return true;
            }
        }
        return false;
    }

    /** @return array{title:string,body:string}|null */
    private static function walletMessage(int $amount, string $reason, ?int $roomId): ?array
    {
        $abs = abs($amount);
        $sign = $amount >= 0 ? '+' : '−';
        if ($reason === 'prize') {
            return ['title' => 'Match prize', 'body' => "$sign$abs Pico coin added to your wallet."];
        }
        if ($reason === 'buy_in') {
            return ['title' => 'Match stake', 'body' => "$sign$abs Pico coin entry fee."];
        }
        if ($reason === 'referral') {
            return ['title' => 'Referral bonus', 'body' => "$sign$abs Pico coin referral reward."];
        }
        if (str_starts_with($reason, 'redeem:')) {
            return ['title' => 'Redeem submitted', 'body' => "$sign$abs Pico coin held for redeem."];
        }
        if (str_starts_with($reason, 'admin:')) {
            return ['title' => 'Balance update', 'body' => "$sign$abs Pico coin (admin adjustment)."];
        }
        if (str_starts_with($reason, 'coin_shop')) {
            return ['title' => 'Coin shop', 'body' => "$sign$abs Pico coin from shop."];
        }
        if (str_starts_with($reason, 'coin_shop_buy')) {
            return ['title' => 'Coin shop purchase', 'body' => "$sign$abs Pico coin pack purchase."];
        }
        return ['title' => 'Wallet update', 'body' => "$sign$abs Pico coin · $reason"];
    }

    private static function eventAlreadyNotified(int $userId, string $eventKey): bool
    {
        self::ensureEventKeyColumn();
        return Db::one(
            'SELECT id FROM user_notifications WHERE user_id = ? AND event_key = ? LIMIT 1',
            [$userId, $eventKey]
        ) !== null;
    }

    private static function insertInbox(int $userId, string $kind, string $title, string $body, ?string $eventKey): void
    {
        self::ensureEventKeyColumn();
        Db::run(
            'INSERT INTO user_notifications (user_id, kind, title, body, event_key) VALUES (?, ?, ?, ?, ?)',
            [$userId, $kind, $title, $body, $eventKey]
        );
    }

    private static function ensureEventKeyColumn(): void
    {
        static $done = false;
        if ($done) {
            return;
        }
        $done = true;
        $pdo = Db::pdo();
        $have = $pdo->query("SHOW COLUMNS FROM user_notifications LIKE 'event_key'")->fetch();
        if ($have === false) {
            $pdo->exec('ALTER TABLE user_notifications ADD COLUMN event_key VARCHAR(80) NULL');
        }
        $idx = $pdo->query("SHOW INDEX FROM user_notifications WHERE Key_name = 'uq_notif_event'")->fetch();
        if ($idx === false) {
            $pdo->exec('CREATE UNIQUE INDEX uq_notif_event ON user_notifications (user_id, event_key)');
        }
    }

    /** @param array<string,string> $data */
    private static function sendFcmToUser(int $userId, string $title, string $body, array $data = []): void
    {
        $rows = Db::all('SELECT token FROM push_tokens WHERE user_id = ?', [$userId]);
        if ($rows === []) {
            return;
        }
        self::sendFcmMulticast(array_column($rows, 'token'), $title, $body, $data);
    }

    /**
     * @param list<string> $tokens
     * @param array<string,string> $data
     * @return array{sent:int,failed:int}
     */
    private static function sendFcmMulticast(array $tokens, string $title, string $body, array $data = []): array
    {
        $key = trim(Config::get('FCM_SERVER_KEY', ''));
        if ($key === '' || !(bool) self::config()['enabled']) {
            return ['sent' => 0, 'failed' => 0];
        }
        $tokens = array_values(array_unique(array_filter(array_map('trim', $tokens))));
        if ($tokens === []) {
            return ['sent' => 0, 'failed' => 0];
        }
        $sent = 0;
        $failed = 0;
        $c = self::config();
        foreach (array_chunk($tokens, 500) as $chunk) {
            $payload = [
                'registration_ids' => $chunk,
                'priority' => 'high',
                'notification' => [
                    'title' => $title,
                    'body' => $body,
                    'android_channel_id' => (string) $c['channelId'],
                ],
                'data' => array_map('strval', $data),
            ];
            $raw = self::httpPost(
                'https://fcm.googleapis.com/fcm/send',
                json_encode($payload, JSON_UNESCAPED_UNICODE),
                ['Authorization: key=' . $key, 'Content-Type: application/json']
            );
            if ($raw === null) {
                $failed += count($chunk);
                continue;
            }
            $json = json_decode($raw, true);
            if (!is_array($json)) {
                $failed += count($chunk);
                continue;
            }
            $sent += (int) ($json['success'] ?? 0);
            $failed += (int) ($json['failure'] ?? 0);
            if (isset($json['results']) && is_array($json['results'])) {
                foreach ($json['results'] as $i => $res) {
                    if (!is_array($res)) {
                        continue;
                    }
                    $err = (string) ($res['error'] ?? '');
                    if ($err === 'NotRegistered' || $err === 'InvalidRegistration') {
                        $bad = $chunk[$i] ?? '';
                        if ($bad !== '') {
                            Db::run('DELETE FROM push_tokens WHERE token = ?', [$bad]);
                        }
                    }
                }
            }
        }
        return ['sent' => $sent, 'failed' => $failed];
    }

    /** @param list<string> $headers */
    private static function httpPost(string $url, string $body, array $headers): ?string
    {
        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            curl_setopt_array($ch, [
                CURLOPT_POST => true,
                CURLOPT_HTTPHEADER => $headers,
                CURLOPT_POSTFIELDS => $body,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => 15,
            ]);
            $out = curl_exec($ch);
            curl_close($ch);
            return is_string($out) ? $out : null;
        }
        $ctx = stream_context_create([
            'http' => [
                'method' => 'POST',
                'header' => implode("\r\n", $headers),
                'content' => $body,
                'timeout' => 15,
                'ignore_errors' => true,
            ],
        ]);
        $out = @file_get_contents($url, false, $ctx);
        return is_string($out) ? $out : null;
    }

    /** @param array<string,mixed> $raw */
    private static function normalize(array $raw): array
    {
        return [
            'enabled' => (bool) ($raw['enabled'] ?? true),
            'depositApproved' => (bool) ($raw['depositApproved'] ?? true),
            'depositRejected' => (bool) ($raw['depositRejected'] ?? true),
            'redeemApproved' => (bool) ($raw['redeemApproved'] ?? true),
            'redeemRejected' => (bool) ($raw['redeemRejected'] ?? true),
            'coinTransfer' => (bool) ($raw['coinTransfer'] ?? true),
            'walletActivity' => (bool) ($raw['walletActivity'] ?? true),
            'challenge' => (bool) ($raw['challenge'] ?? true),
            'adminBroadcast' => (bool) ($raw['adminBroadcast'] ?? true),
            'channelId' => preg_replace('/[^a-zA-Z0-9_]/', '', (string) ($raw['channelId'] ?? self::DEFAULTS['channelId'])) ?: 'pikope_default',
            'channelName' => mb_substr(trim((string) ($raw['channelName'] ?? self::DEFAULTS['channelName'])), 0, 40) ?: 'PikoPe',
        ];
    }

    /** @param array<int|string,mixed> $params */
    private static function n(string $sql, array $params = []): int
    {
        return (int) Db::one($sql, $params)['n'];
    }
}
