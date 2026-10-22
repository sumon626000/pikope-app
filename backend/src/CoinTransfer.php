<?php
declare(strict_types=1);

namespace App;

/** Send Pico coin to another player by 6-digit game ID (registered accounts only). */
final class CoinTransfer
{
    public const DEFAULTS = [
        'enabled' => true,
        'feePercent' => 10,
        'minCoins' => 10,
        'maxCoins' => 500000,
    ];

    /** @var array<string,mixed>|null */
    private static ?array $config = null;

    public static function ensureTable(): void
    {
        Db::run(
            'CREATE TABLE IF NOT EXISTS coin_transfers (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                from_user_id BIGINT UNSIGNED NOT NULL,
                to_user_id BIGINT UNSIGNED NOT NULL,
                amount INT NOT NULL,
                fee INT NOT NULL,
                received INT NOT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                KEY idx_transfer_from (from_user_id, created_at),
                KEY idx_transfer_to (to_user_id, created_at),
                CONSTRAINT fk_transfer_from FOREIGN KEY (from_user_id) REFERENCES users (id) ON DELETE CASCADE,
                CONSTRAINT fk_transfer_to FOREIGN KEY (to_user_id) REFERENCES users (id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
    }

    /** @return array<string,mixed> */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'coin_transfer'");
        $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
        self::$config = self::normalize(array_merge(self::DEFAULTS, array_intersect_key($saved, self::DEFAULTS)));
        return self::$config;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('coin_transfer', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode(self::normalize($raw))]
        );
        self::$config = null;
    }

    /** @return array<string,mixed> */
    public static function publicConfig(): array
    {
        $c = self::config();
        return [
            'enabled' => (bool) $c['enabled'],
            'feePercent' => (int) $c['feePercent'],
            'minCoins' => (int) $c['minCoins'],
            'maxCoins' => (int) $c['maxCoins'],
        ];
    }

    /** @return array<string,mixed>|null */
    public static function lookupProfile(string $gameId, int $viewerId): ?array
    {
        $code = self::normalizeGameId($gameId);
        $u = Db::one(
            'SELECT id, display_name, avatar, is_guest, is_bot, banned, referral_code FROM users WHERE referral_code = ?',
            [$code]
        );
        if ($u === null || (int) $u['is_bot'] === 1 || (int) $u['banned'] === 1) {
            return null;
        }
        if ((int) $u['is_guest'] === 1) {
            return ['eligible' => false, 'reason' => 'guest'];
        }
        if ((int) $u['id'] === $viewerId) {
            return ['eligible' => false, 'reason' => 'self'];
        }
        return [
            'eligible' => true,
            'gameId' => $code,
            'name' => $u['display_name'],
            'avatar' => $u['avatar'],
        ];
    }

    /** @return array<string,mixed> */
    public static function send(int $fromId, string $toGameId, int $amount): array
    {
        $c = self::config();
        if (!(bool) $c['enabled']) {
            throw ApiError::badRequest('Coin transfer is turned off.', 'transfer_disabled');
        }
        $min = (int) $c['minCoins'];
        $max = (int) $c['maxCoins'];
        if ($amount < $min || $amount > $max) {
            throw ApiError::badRequest("Transfer between $min and $max Pico coin.", 'bad_amount');
        }
        $target = self::lookupProfile($toGameId, $fromId);
        if ($target === null) {
            AdminAlert::signal('transfer_abuse', 'Invalid transfer target ID', "gameId=$toGameId", $fromId);
            throw ApiError::notFound('No registered player with that game ID.', 'bad_recipient');
        }
        if (($target['eligible'] ?? false) !== true) {
            $why = (string) ($target['reason'] ?? 'unknown');
            AdminAlert::signal('transfer_abuse', 'Transfer blocked', "reason=$why gameId=$toGameId amount=$amount", $fromId);
            throw ApiError::badRequest('Only registered players can receive transfers.', 'bad_recipient');
        }
        $toId = (int) Db::one('SELECT id FROM users WHERE referral_code = ?', [self::normalizeGameId($toGameId)])['id'];
        $feePct = max(0, min(50, (int) $c['feePercent']));
        $fee = intdiv($amount * $feePct, 100);
        $total = $amount + $fee;

        $payload = Db::transaction(static function () use ($fromId, $toId, $amount, $fee, $total): array {
            self::ensureTable();
            Economy::move($fromId, -$total, 'transfer_out');
            Economy::move($toId, $amount, 'transfer_in');
            Db::run(
                'INSERT INTO coin_transfers (from_user_id, to_user_id, amount, fee, received) VALUES (?, ?, ?, ?, ?)',
                [$fromId, $toId, $amount, $fee, $amount]
            );
            $id = Db::lastId();
            $row = Db::one(
                'SELECT t.*, fu.display_name AS from_name, fu.referral_code AS from_code,
                        tu.display_name AS to_name, tu.referral_code AS to_code
                 FROM coin_transfers t
                 JOIN users fu ON fu.id = t.from_user_id
                 JOIN users tu ON tu.id = t.to_user_id
                 WHERE t.id = ?',
                [$id]
            );
            $toName = (string) ($row['to_name'] ?? '');
            return ['row' => $row, 'fromId' => $fromId, 'toId' => $toId, 'toName' => $toName, 'transferId' => $id];
        });

        $from = Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$fromId]));
        $senderName = (string) ($from['displayName'] ?? 'Player');
        try {
            Push::notifyUser(
                $payload['toId'],
                'coin_received',
                'Pico coin received',
                "$senderName sent you $amount Pico coin.",
                [],
                'transfer_in:' . $payload['transferId']
            );
            Push::notifyUser(
                $fromId,
                'coin_sent',
                'Transfer sent',
                "You sent $amount to {$payload['toName']} (fee $fee).",
                [],
                'transfer_out:' . $payload['transferId']
            );
        } catch (\Throwable $e) {
            error_log('[transfer] push failed: ' . $e->getMessage());
        }

        return [
            'transfer' => self::publicRow($payload['row'], $fromId),
            'user' => $from,
        ];
    }

    /** @return list<array<string,mixed>> */
    public static function historyForUser(int $userId, int $limit = 40): array
    {
        self::ensureTable();
        $limit = max(1, min(100, $limit));
        $rows = Db::all(
            'SELECT t.*, fu.display_name AS from_name, fu.referral_code AS from_code,
                    tu.display_name AS to_name, tu.referral_code AS to_code
             FROM coin_transfers t
             JOIN users fu ON fu.id = t.from_user_id
             JOIN users tu ON tu.id = t.to_user_id
             WHERE t.from_user_id = ? OR t.to_user_id = ?
             ORDER BY t.id DESC LIMIT ' . $limit,
            [$userId, $userId]
        );
        return array_map(static fn (array $r): array => self::publicRow($r, $userId), $rows);
    }

    /** @param array<string,mixed> $r */
    public static function historyRow(array $r, int $viewerId): array
    {
        return self::publicRow($r, $viewerId);
    }

    /** @param array<string,mixed> $r */
    private static function publicRow(array $r, ?int $viewerId = null): array
    {
        $fromId = (int) $r['from_user_id'];
        $toId = (int) $r['to_user_id'];
        $out = [
            'id' => (int) $r['id'],
            'amount' => (int) $r['amount'],
            'fee' => (int) $r['fee'],
            'received' => (int) $r['received'],
            'fromUserId' => $fromId,
            'toUserId' => $toId,
            'fromName' => $r['from_name'] ?? '',
            'toName' => $r['to_name'] ?? '',
            'fromGameId' => $r['from_code'] ?? null,
            'toGameId' => $r['to_code'] ?? null,
            'createdAt' => strtotime((string) $r['created_at']) * 1000,
        ];
        if ($viewerId !== null) {
            $out['direction'] = $viewerId === $fromId ? 'sent' : 'received';
        }
        return $out;
    }

    private static function normalizeGameId(string $raw): string
    {
        $d = preg_replace('/\D/', '', trim($raw)) ?? '';
        if (strlen($d) !== 6) {
            throw ApiError::badRequest('Game ID must be 6 digits.', 'bad_game_id');
        }
        return $d;
    }

    /** @param array<string,mixed> $raw */
    private static function normalize(array $raw): array
    {
        return [
            'enabled' => (bool) ($raw['enabled'] ?? true),
            'feePercent' => max(0, min(50, (int) ($raw['feePercent'] ?? 10))),
            'minCoins' => max(1, min(10_000_000, (int) ($raw['minCoins'] ?? 10))),
            'maxCoins' => max(1, min(50_000_000, (int) ($raw['maxCoins'] ?? 500000))),
        ];
    }
}
