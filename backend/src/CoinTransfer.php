<?php
declare(strict_types=1);

namespace App;

/** Send Pico coin to another player by 6-digit game ID (registered accounts only). */
final class CoinTransfer
{
    public const DEFAULTS = [
        'enabled' => true,
        'feePercent' => 10,
        'minCoins' => 50,
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
                idempotency_key VARCHAR(64) NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                KEY idx_transfer_from (from_user_id, created_at),
                KEY idx_transfer_to (to_user_id, created_at),
                UNIQUE KEY uq_transfer_idem (from_user_id, idempotency_key),
                CONSTRAINT fk_transfer_from FOREIGN KEY (from_user_id) REFERENCES users (id) ON DELETE CASCADE,
                CONSTRAINT fk_transfer_to FOREIGN KEY (to_user_id) REFERENCES users (id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
        // Older installs: add column + unique index if missing.
        try {
            $col = Db::one(
                "SELECT COLUMN_NAME FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'coin_transfers' AND COLUMN_NAME = 'idempotency_key'"
            );
            if ($col === null) {
                Db::run('ALTER TABLE coin_transfers ADD COLUMN idempotency_key VARCHAR(64) NULL AFTER received');
            }
        } catch (\Throwable $e) {
            error_log('[transfer] ensure idempotency column: ' . $e->getMessage());
        }
        try {
            $idx = Db::one(
                "SELECT INDEX_NAME FROM information_schema.STATISTICS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'coin_transfers' AND INDEX_NAME = 'uq_transfer_idem'"
            );
            if ($idx === null) {
                Db::run('ALTER TABLE coin_transfers ADD UNIQUE KEY uq_transfer_idem (from_user_id, idempotency_key)');
            }
        } catch (\Throwable $e) {
            error_log('[transfer] ensure idempotency index: ' . $e->getMessage());
        }
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
    public static function send(int $fromId, string $toGameId, int $amount, ?string $idempotencyKey = null): array
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
        $key = self::normalizeIdempotencyKey($idempotencyKey);
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

        // DDL must not run inside Db::transaction (MySQL implicit commit breaks commit()).
        self::ensureTable();

        // Replay: same client key → prior result (no second debit).
        if ($key !== null) {
            $prior = self::findByIdempotency($fromId, $key);
            if ($prior !== null) {
                return self::responseFromRow($prior, $fromId, $toGameId, $amount, $fee);
            }
        }

        $payload = Db::transaction(static function () use ($fromId, $toId, $amount, $fee, $total, $key): array {
            // Lock both wallets in id order to avoid deadlocks / double-spend races.
            $first = min($fromId, $toId);
            $second = max($fromId, $toId);
            Db::one('SELECT id FROM users WHERE id = ? FOR UPDATE', [$first]);
            if ($second !== $first) {
                Db::one('SELECT id FROM users WHERE id = ? FOR UPDATE', [$second]);
            }

            if ($key !== null) {
                $existing = Db::one(
                    'SELECT id FROM coin_transfers WHERE from_user_id = ? AND idempotency_key = ?',
                    [$fromId, $key]
                );
                if ($existing !== null) {
                    $row = self::loadJoinedRow((int) $existing['id']);
                    return [
                        'row' => $row,
                        'fromId' => $fromId,
                        'toId' => $toId,
                        'toName' => (string) ($row['to_name'] ?? ''),
                        'transferId' => (int) $existing['id'],
                        'replay' => true,
                    ];
                }
            }

            try {
                Db::run(
                    'INSERT INTO coin_transfers (from_user_id, to_user_id, amount, fee, received, idempotency_key)
                     VALUES (?, ?, ?, ?, ?, ?)',
                    [$fromId, $toId, $amount, $fee, $amount, $key]
                );
            } catch (\PDOException $e) {
                if (($e->errorInfo[1] ?? 0) === 1062 && $key !== null) {
                    $existing = Db::one(
                        'SELECT id FROM coin_transfers WHERE from_user_id = ? AND idempotency_key = ?',
                        [$fromId, $key]
                    );
                    if ($existing !== null) {
                        $row = self::loadJoinedRow((int) $existing['id']);
                        if ($row === null) {
                            throw new \RuntimeException('Transfer row missing after idempotency hit');
                        }
                        return [
                            'row' => $row,
                            'fromId' => $fromId,
                            'toId' => $toId,
                            'toName' => (string) ($row['to_name'] ?? ''),
                            'transferId' => (int) $existing['id'],
                            'replay' => true,
                        ];
                    }
                }
                throw $e;
            }
            $id = Db::lastId();
            Economy::move($fromId, -$total, 'transfer_out:' . $id);
            Economy::move($toId, $amount, 'transfer_in:' . $id);
            $row = self::loadJoinedRow($id);
            if ($row === null) {
                throw new \RuntimeException('Transfer row missing after insert');
            }
            $toName = (string) ($row['to_name'] ?? '');
            return ['row' => $row, 'fromId' => $fromId, 'toId' => $toId, 'toName' => $toName, 'transferId' => $id];
        });

        if (($payload['replay'] ?? false) === true) {
            return self::responseFromRow($payload['row'], $fromId, $toGameId, $amount, $fee);
        }

        $senderName = (string) ($payload['row']['from_name'] ?? 'Player');
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

        try {
            $transfer = self::publicRow($payload['row'], $fromId);
        } catch (\Throwable $e) {
            error_log('[transfer] publicRow failed: ' . $e->getMessage());
            $transfer = [
                'id' => (int) $payload['transferId'],
                'amount' => $amount,
                'fee' => $fee,
                'received' => $amount,
                'toName' => $payload['toName'],
                'toGameId' => self::normalizeGameId($toGameId),
                'direction' => 'sent',
            ];
        }

        return [
            'transfer' => $transfer,
            'user' => self::senderSnapshot($fromId),
        ];
    }

    /** Wallet refresh for the sender; must not fail after coins have moved. */
    private static function senderSnapshot(int $fromId): array
    {
        try {
            $fromRow = Db::one('SELECT * FROM users WHERE id = ?', [$fromId]);
            if ($fromRow === null) {
                throw new \RuntimeException('Account missing after transfer');
            }
            return Auth::publicUser($fromRow);
        } catch (\Throwable $e) {
            error_log('[transfer] sender snapshot failed: ' . $e->getMessage());
            $row = Db::one('SELECT id, display_name, coins, redeemable_coins FROM users WHERE id = ?', [$fromId]) ?? [];
            return [
                'id' => $fromId,
                'displayName' => (string) ($row['display_name'] ?? 'Player'),
                'coins' => (int) ($row['coins'] ?? 0),
                'redeemableCoins' => (int) ($row['redeemable_coins'] ?? 0),
            ];
        }
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

    private static function normalizeIdempotencyKey(?string $raw): ?string
    {
        if ($raw === null) {
            return null;
        }
        $key = trim($raw);
        if ($key === '') {
            return null;
        }
        if (strlen($key) < 8 || strlen($key) > 64 || !preg_match('/^[A-Za-z0-9._:-]+$/', $key)) {
            throw ApiError::badRequest('Invalid idempotency key.', 'bad_idempotency');
        }
        return $key;
    }

    /** @return array<string,mixed>|null */
    private static function findByIdempotency(int $fromId, string $key): ?array
    {
        $row = Db::one(
            'SELECT id FROM coin_transfers WHERE from_user_id = ? AND idempotency_key = ?',
            [$fromId, $key]
        );
        if ($row === null) {
            return null;
        }
        return self::loadJoinedRow((int) $row['id']);
    }

    /** @return array<string,mixed>|null */
    private static function loadJoinedRow(int $id): ?array
    {
        return Db::one(
            'SELECT t.*, fu.display_name AS from_name, fu.referral_code AS from_code,
                    tu.display_name AS to_name, tu.referral_code AS to_code
             FROM coin_transfers t
             JOIN users fu ON fu.id = t.from_user_id
             JOIN users tu ON tu.id = t.to_user_id
             WHERE t.id = ?',
            [$id]
        );
    }

    /**
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    private static function responseFromRow(
        array $row,
        int $fromId,
        string $toGameId,
        int $amount,
        int $fee
    ): array {
        try {
            $transfer = self::publicRow($row, $fromId);
        } catch (\Throwable $e) {
            $transfer = [
                'id' => (int) ($row['id'] ?? 0),
                'amount' => $amount,
                'fee' => $fee,
                'received' => $amount,
                'toName' => (string) ($row['to_name'] ?? ''),
                'toGameId' => self::normalizeGameId($toGameId),
                'direction' => 'sent',
            ];
        }
        return [
            'transfer' => $transfer,
            'user' => self::senderSnapshot($fromId),
        ];
    }

    /** @param array<string,mixed> $raw */
    private static function normalize(array $raw): array
    {
        return [
            'enabled' => (bool) ($raw['enabled'] ?? true),
            'feePercent' => max(0, min(50, (int) ($raw['feePercent'] ?? 10))),
            'minCoins' => max(1, min(10_000_000, (int) ($raw['minCoins'] ?? 50))),
            'maxCoins' => max(1, min(50_000_000, (int) ($raw['maxCoins'] ?? 500000))),
        ];
    }
}
