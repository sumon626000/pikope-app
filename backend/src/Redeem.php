<?php
declare(strict_types=1);

namespace App;

/** Cash-out: players redeem Pico coin to a mobile wallet (bKash / Nagad / Rocket). */
final class Redeem
{
    public const DEFAULTS = [
        'enabled' => true,
        'minCoins' => 300,
        'maxCoins' => 200000,
        'maxPendingPerUser' => 2,
        'coinPerBdt' => 1,
    ];

    public const PROVIDERS = ['bkash' => 'bKash', 'nagad' => 'Nagad', 'rocket' => 'Rocket'];

    /** @var array<string,mixed>|null */
    private static ?array $config = null;

    /** @return array<string,mixed> */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'redeem'");
        $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
        self::$config = self::normalize(array_merge(self::DEFAULTS, array_intersect_key($saved, self::DEFAULTS)));
        return self::$config;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('redeem', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
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
            'minCoins' => (int) $c['minCoins'],
            'maxCoins' => (int) $c['maxCoins'],
            'maxPendingPerUser' => (int) $c['maxPendingPerUser'],
            'coinPerBdt' => (int) $c['coinPerBdt'],
            'providers' => array_map(
                static fn (string $id, string $label): array => ['id' => $id, 'label' => $label],
                array_keys(self::PROVIDERS),
                array_values(self::PROVIDERS)
            ),
        ];
    }

    /** @return array<string,mixed> */
    public static function create(int $userId, int $coins, string $provider, string $walletNumber): array
    {
        $c = self::config();
        if (!$c['enabled']) {
            throw ApiError::badRequest('Redeem is turned off right now.', 'redeem_disabled');
        }
        $provider = strtolower(trim($provider));
        if (!isset(self::PROVIDERS[$provider])) {
            throw ApiError::badRequest('Choose bKash, Nagad or Rocket.', 'bad_wallet');
        }
        $wallet = self::normalizeWallet($walletNumber);
        $min = (int) $c['minCoins'];
        $max = (int) $c['maxCoins'];
        if ($coins < $min || $coins > $max) {
            AdminAlert::signal('redeem_abuse', 'Redeem out of range', "user=$userId coins=$coins", $userId);
            throw ApiError::badRequest("Redeem between $min and $max Pico coin.", 'bad_amount');
        }
        Economy::ensureRedeemableColumn();
        $rate = max(1, (int) $c['coinPerBdt']);
        $bdt = intdiv($coins, $rate);
        if ($bdt < 1) {
            throw ApiError::badRequest('Amount too small.', 'bad_amount');
        }
        $maxPending = (int) $c['maxPendingPerUser'];

        return Db::transaction(static function () use ($userId, $coins, $bdt, $provider, $wallet, $maxPending): array {
            $u = Db::one('SELECT id, redeemable_coins FROM users WHERE id = ? FOR UPDATE', [$userId]);
            if ($u === null) {
                throw ApiError::notFound('No such player');
            }
            if ($coins > (int) $u['redeemable_coins']) {
                AdminAlert::signal(
                    'redeem_abuse',
                    'Illegal redeem attempt (win balance)',
                    "user=$userId coins=$coins redeemable={$u['redeemable_coins']}",
                    $userId
                );
                throw ApiError::conflict('Not enough redeemable win balance. Deposits cannot be cashed out.', 'not_enough_redeemable');
            }
            $pending = (int) Db::one(
                "SELECT COUNT(*) AS n FROM redeem_requests WHERE user_id = ? AND status = 'pending'",
                [$userId]
            )['n'];
            if ($pending >= $maxPending) {
                throw ApiError::conflict('You already have pending redeem requests. Wait for admin review.', 'redeem_pending');
            }
            Db::run(
                'INSERT INTO redeem_requests (user_id, coins, bdt_amount, wallet_provider, wallet_number, status)
                 VALUES (?, ?, ?, ?, ?, \'pending\')',
                [$userId, $coins, $bdt, $provider, $wallet]
            );
            $id = Db::lastId();
            Economy::move($userId, -$coins, 'redeem:' . $id);
            $row = Db::one('SELECT * FROM redeem_requests WHERE id = ?', [$id]);
            $out = self::publicRow($row);
            return [
                'request' => $out,
                'user' => Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$userId])),
            ];
        });
    }

    public static function approve(int $id, string $note = ''): void
    {
        Db::transaction(static function () use ($id, $note): void {
            $r = Db::one('SELECT * FROM redeem_requests WHERE id = ? FOR UPDATE', [$id]);
            if ($r === null || $r['status'] !== 'pending') {
                throw ApiError::badRequest('Request not found or already reviewed.', 'bad_redeem');
            }
            Db::run(
                'UPDATE redeem_requests SET status = \'approved\', admin_note = ?, reviewed_at = NOW() WHERE id = ?',
                [trim($note) === '' ? null : trim($note), $id]
            );
            Push::notifyUser(
                (int) $r['user_id'],
                'redeem_approved',
                'Redeem approved',
                (int) $r['bdt_amount'] . ' BDT will be sent to your wallet.',
                [],
                'redeem_appr:' . $id
            );
        });
    }

    /** Player cancels a pending request before admin review; coins are refunded. */
    public static function cancelByUser(int $userId, int $id): array
    {
        return Db::transaction(static function () use ($userId, $id): array {
            $r = Db::one('SELECT * FROM redeem_requests WHERE id = ? FOR UPDATE', [$id]);
            if ($r === null || (int) $r['user_id'] !== $userId) {
                throw ApiError::notFound('Request not found.');
            }
            if ($r['status'] !== 'pending') {
                throw ApiError::conflict('This request can no longer be cancelled.', 'redeem_not_pending');
            }
            Economy::move($userId, (int) $r['coins'], 'redeem_refund:' . $id);
            Db::run(
                'UPDATE redeem_requests SET status = \'cancelled\', admin_note = ?, reviewed_at = NOW() WHERE id = ?',
                ['Cancelled by player', $id]
            );
            $row = Db::one('SELECT * FROM redeem_requests WHERE id = ?', [$id]);
            Push::notifyUser(
                $userId,
                'redeem_cancelled',
                'Redeem cancelled',
                (int) $row['coins'] . ' Pico coin returned to your wallet.',
                [],
                'redeem_cancel:' . $id
            );
            return [
                'request' => self::publicRow($row),
                'user' => Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$userId])),
            ];
        });
    }

    public static function reject(int $id, string $note = ''): void
    {
        Db::transaction(static function () use ($id, $note): void {
            $r = Db::one('SELECT * FROM redeem_requests WHERE id = ? FOR UPDATE', [$id]);
            if ($r === null || $r['status'] !== 'pending') {
                throw ApiError::badRequest('Request not found or already reviewed.', 'bad_redeem');
            }
            Economy::move((int) $r['user_id'], (int) $r['coins'], 'redeem_refund:' . $id);
            Db::run(
                'UPDATE redeem_requests SET status = \'rejected\', admin_note = ?, reviewed_at = NOW() WHERE id = ?',
                [trim($note) === '' ? null : trim($note), $id]
            );
            $msg = trim($note) !== '' ? trim($note) : 'Your redeem request was rejected and Pico coin was refunded.';
            Push::notifyUser((int) $r['user_id'], 'redeem_rejected', 'Redeem rejected', $msg, [], 'redeem_rej:' . $id);
        });
    }

    /** @return list<array<string,mixed>> */
    public static function listForUser(int $userId, int $limit = 40): array
    {
        $rows = Db::all(
            'SELECT * FROM redeem_requests WHERE user_id = ? ORDER BY id DESC LIMIT ' . max(1, min(100, $limit)),
            [$userId]
        );
        return array_map(self::publicRow(...), $rows);
    }

    /** Unified timeline for the app (matches, wallet, redeems). */
    public static function activityFeed(int $userId, int $limit = 60): array
    {
        $limit = max(10, min(100, $limit));
        $items = [];

        foreach (Db::all(
            'SELECT game, mode, won, coins_delta, stake, prize, UNIX_TIMESTAMP(created_at) AS ts
             FROM match_results WHERE user_id = ? ORDER BY id DESC LIMIT ' . $limit,
            [$userId]
        ) as $r) {
            $items[] = [
                'kind' => 'match',
                'at' => (int) $r['ts'] * 1000,
                'game' => $r['game'],
                'mode' => $r['mode'],
                'won' => (bool) $r['won'],
                'coins' => (int) $r['coins_delta'],
                'stake' => (int) $r['stake'],
                'prize' => (int) $r['prize'],
            ];
        }

        foreach (Db::all(
            'SELECT amount, balance_after, reason, UNIX_TIMESTAMP(created_at) AS ts
             FROM wallet_tx WHERE user_id = ? AND currency = \'coins\' ORDER BY id DESC LIMIT ' . $limit,
            [$userId]
        ) as $r) {
            $reason = (string) $r['reason'];
            if (str_starts_with($reason, 'redeem:') || str_starts_with($reason, 'deposit:')
                || $reason === 'transfer_out' || $reason === 'transfer_in') {
                continue;
            }
            $items[] = [
                'kind' => 'wallet',
                'at' => (int) $r['ts'] * 1000,
                'amount' => (int) $r['amount'],
                'balanceAfter' => (int) $r['balance_after'],
                'reason' => $r['reason'],
                'label' => self::walletLabel((string) $r['reason']),
            ];
        }

        foreach (Db::all(
            'SELECT * FROM redeem_requests WHERE user_id = ? ORDER BY id DESC LIMIT ' . $limit,
            [$userId]
        ) as $r) {
            $items[] = [
                'kind' => 'redeem',
                'at' => strtotime((string) $r['created_at']) * 1000,
            ] + self::publicRow($r);
        }

        CoinTransfer::ensureTable();
        foreach (Db::all(
            'SELECT t.*, fu.display_name AS from_name, fu.referral_code AS from_code,
                    tu.display_name AS to_name, tu.referral_code AS to_code
             FROM coin_transfers t
             JOIN users fu ON fu.id = t.from_user_id
             JOIN users tu ON tu.id = t.to_user_id
             WHERE t.from_user_id = ? OR t.to_user_id = ?
             ORDER BY t.id DESC LIMIT ' . $limit,
            [$userId, $userId]
        ) as $r) {
            $items[] = [
                'kind' => 'transfer',
                'at' => (int) strtotime((string) $r['created_at']) * 1000,
            ] + CoinTransfer::historyRow($r, $userId);
        }

        $items = array_merge($items, CoinDeposit::activityItems($userId, $limit));

        usort($items, static fn (array $a, array $b): int => ($b['at'] <=> $a['at']));
        return array_slice($items, 0, $limit);
    }

    public static function walletLabel(string $reason): string
    {
        if (str_starts_with($reason, 'coin_shop_buy:')) {
            return 'Coin pack purchase';
        }
        if (str_starts_with($reason, 'coin_shop:')) {
            return 'Coin pack received';
        }
        if ($reason === 'buy_in') {
            return 'Match buy-in';
        }
        if ($reason === 'prize') {
            return 'Match prize';
        }
        if (str_starts_with($reason, 'redeem:')) {
            return 'Redeem request';
        }
        if (str_starts_with($reason, 'redeem_refund:')) {
            return 'Redeem refunded';
        }
        if ($reason === 'transfer_out') {
            return 'Coin transfer sent';
        }
        if ($reason === 'transfer_in') {
            return 'Coin transfer received';
        }
        $dep = CoinDeposit::walletLabel($reason);
        if ($dep !== null) {
            return $dep;
        }
        if ($reason === 'welcome') {
            return 'Welcome bonus';
        }
        if ($reason === 'daily') {
            return 'Daily bonus';
        }
        if ($reason === 'referral') {
            return 'Referral reward';
        }
        return $reason;
    }

    /** @param array<string,mixed> $r */
    public static function publicRow(array $r): array
    {
        $prov = (string) $r['wallet_provider'];
        return [
            'id' => (int) $r['id'],
            'coins' => (int) $r['coins'],
            'bdt' => (int) $r['bdt_amount'],
            'walletProvider' => $prov,
            'walletProviderLabel' => self::PROVIDERS[$prov] ?? $prov,
            'walletNumber' => self::maskWallet((string) $r['wallet_number']),
            'walletNumberFull' => (string) $r['wallet_number'],
            'status' => $r['status'],
            'canCancel' => $r['status'] === 'pending',
            'adminNote' => $r['admin_note'],
            'createdAt' => strtotime((string) $r['created_at']) * 1000,
            'reviewedAt' => $r['reviewed_at'] !== null ? strtotime((string) $r['reviewed_at']) * 1000 : null,
        ];
    }

    /** @param array<string,mixed> $r Admin view with player info */
    public static function adminRow(array $r): array
    {
        return self::publicRow($r) + [
            'userId' => (int) $r['user_id'],
            'displayName' => $r['display_name'] ?? '',
            'playerPhone' => isset($r['phone']) && $r['phone'] !== null && $r['phone'] !== ''
                ? Phone::display((string) $r['phone'])
                : null,
        ];
    }

    private static function maskWallet(string $n): string
    {
        $d = preg_replace('/\D/', '', $n) ?? '';
        if (strlen($d) <= 4) {
            return $d;
        }
        return str_repeat('*', max(0, strlen($d) - 4)) . substr($d, -4);
    }

    /** @throws ApiError */
    private static function normalizeWallet(string $raw): string
    {
        $d = preg_replace('/\D/', '', trim($raw)) ?? '';
        if (preg_match('/^1[3-9]\d{8}$/', $d) === 1) {
            return $d;
        }
        if (preg_match('/^8801[3-9]\d{8}$/', $d) === 1) {
            return substr($d, 3);
        }
        if (preg_match('/^01[3-9]\d{8}$/', $d) === 1) {
            return substr($d, 1);
        }
        throw ApiError::badRequest('Enter a valid wallet number (11 digits).', 'bad_wallet');
    }

    /** @param array<string,mixed> $raw */
    private static function normalize(array $raw): array
    {
        return [
            'enabled' => (bool) ($raw['enabled'] ?? true),
            'minCoins' => max(100, min(10_000_000, (int) ($raw['minCoins'] ?? 300))),
            'maxCoins' => max(100, min(50_000_000, (int) ($raw['maxCoins'] ?? 200000))),
            'maxPendingPerUser' => max(1, min(10, (int) ($raw['maxPendingPerUser'] ?? 2))),
            'coinPerBdt' => max(1, min(1000, (int) ($raw['coinPerBdt'] ?? 1))),
        ];
    }
}
