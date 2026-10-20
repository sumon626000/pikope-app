<?php
declare(strict_types=1);

namespace App;

/** Manual top-up: player pays bKash/Nagad to agent numbers, submits TrxID; admin approves coins. */
final class CoinDeposit
{
    public const DEFAULTS = [
        'enabled' => true,
        'minBdt' => 100,
        'maxBdt' => 50000,
        'coinPerBdt' => 1,
        'maxPendingPerUser' => 3,
        'bkashNumber' => '',
        'nagadNumber' => '',
        'rocketNumber' => '',
        'paymentType' => 'personal',
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
        $row = Db::one("SELECT v FROM settings WHERE k = 'coin_deposit'");
        $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
        self::$config = self::normalize(array_merge(self::DEFAULTS, array_intersect_key($saved, self::DEFAULTS)));
        return self::$config;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('coin_deposit', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode(self::normalize($raw))]
        );
        self::$config = null;
    }

    /** @return array<string,mixed> */
    public static function publicConfig(): array
    {
        $c = self::config();
        $agents = [];
        foreach (self::PROVIDERS as $id => $label) {
            $key = $id . 'Number';
            $num = trim((string) ($c[$key] ?? ''));
            if ($num !== '') {
                $agents[] = ['id' => $id, 'label' => $label, 'number' => self::formatAgentNumber($num)];
            }
        }
        return [
            'enabled' => (bool) $c['enabled'],
            'manualEnabled' => (bool) $c['enabled'],
            'autoEnabled' => class_exists(ZiniPay::class) && ZiniPay::publicEnabled(),
            'minBdt' => (int) $c['minBdt'],
            'maxBdt' => (int) $c['maxBdt'],
            'coinPerBdt' => (int) $c['coinPerBdt'],
            'maxPendingPerUser' => (int) $c['maxPendingPerUser'],
            'paymentType' => (string) $c['paymentType'],
            'agents' => $agents,
        ];
    }

    /** @return array<string,mixed> */
    public static function create(int $userId, string $provider, int $bdt, string $trxId, string $payerNumber): array
    {
        $c = self::config();
        if (!$c['enabled']) {
            throw ApiError::badRequest('Manual coin add is turned off.', 'deposit_disabled');
        }
        if (self::publicConfig()['agents'] === []) {
            throw ApiError::badRequest('Payment numbers are not set yet. Contact support.', 'deposit_no_agent');
        }
        $provider = strtolower(trim($provider));
        if (!isset(self::PROVIDERS[$provider])) {
            throw ApiError::badRequest('Choose bKash or Nagad.', 'bad_provider');
        }
        $agentKey = $provider . 'Number';
        if (trim((string) $c[$agentKey]) === '') {
            throw ApiError::badRequest('That wallet is not available for deposit.', 'bad_provider');
        }
        $min = (int) $c['minBdt'];
        $max = (int) $c['maxBdt'];
        if ($bdt < $min || $bdt > $max) {
            throw ApiError::badRequest("Amount must be between $min and $max BDT.", 'bad_amount');
        }
        $trxId = self::normalizeTrx($trxId);
        $payer = self::normalizePayer($payerNumber);
        $rate = max(1, (int) $c['coinPerBdt']);
        // Promo bonus (if any) is fixed here — approve credits exactly this row, never twice.
        $coins = Promotions::depositCoins($bdt, $rate);

        $maxPending = (int) $c['maxPendingPerUser'];

        return Db::transaction(static function () use ($userId, $provider, $payer, $trxId, $bdt, $coins, $maxPending): array {
            Db::one('SELECT id FROM users WHERE id = ? FOR UPDATE', [$userId]);
            $dup = Db::one(
                "SELECT id FROM coin_deposit_requests WHERE trx_id = ? AND provider = ? AND status IN ('pending','approved')",
                [$trxId, $provider]
            );
            if ($dup !== null) {
                throw ApiError::conflict('This TrxID was already used.', 'trx_used');
            }
            $pending = (int) Db::one(
                "SELECT COUNT(*) AS n FROM coin_deposit_requests WHERE user_id = ? AND status = 'pending'",
                [$userId]
            )['n'];
            if ($pending >= $maxPending) {
                throw ApiError::conflict('Wait for your pending deposits to be reviewed.', 'deposit_pending');
            }
            try {
                Db::run(
                    'INSERT INTO coin_deposit_requests (user_id, provider, payer_number, trx_id, bdt_amount, coins, status)
                     VALUES (?, ?, ?, ?, ?, ?, \'pending\')',
                    [$userId, $provider, $payer, $trxId, $bdt, $coins]
                );
            } catch (\PDOException $e) {
                if (($e->errorInfo[1] ?? 0) === 1062) {
                    throw ApiError::conflict('This TrxID was already used.', 'trx_used');
                }
                throw $e;
            }
            $row = Db::one('SELECT * FROM coin_deposit_requests WHERE id = ?', [Db::lastId()]);
            return [
                'request' => self::publicRow($row),
                'user' => Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$userId])),
            ];
        });
    }

    public static function approve(int $id, string $note = ''): void
    {
        Db::transaction(static function () use ($id, $note): void {
            $r = Db::one('SELECT * FROM coin_deposit_requests WHERE id = ? FOR UPDATE', [$id]);
            if ($r === null || $r['status'] !== 'pending') {
                throw ApiError::badRequest('Request not found or already reviewed.', 'bad_deposit');
            }
            $already = Db::one(
                'SELECT id FROM wallet_tx WHERE user_id = ? AND reason = ? LIMIT 1',
                [(int) $r['user_id'], 'deposit:' . $id]
            );
            if ($already !== null) {
                throw ApiError::conflict('This deposit was already credited.', 'deposit_paid');
            }
            Economy::move((int) $r['user_id'], (int) $r['coins'], 'deposit:' . $id);
            Db::run(
                'UPDATE coin_deposit_requests SET status = \'approved\', admin_note = ?, reviewed_at = NOW() WHERE id = ?',
                [trim($note) === '' ? null : trim($note), $id]
            );
            Push::notifyUser(
                (int) $r['user_id'],
                'deposit_approved',
                'Coin add approved',
                '+' . (int) $r['coins'] . ' Pico coin added to your wallet.'
            );
        });
    }

    public static function reject(int $id, string $note = ''): void
    {
        Db::transaction(static function () use ($id, $note): void {
            $r = Db::one('SELECT * FROM coin_deposit_requests WHERE id = ? FOR UPDATE', [$id]);
            if ($r === null || $r['status'] !== 'pending') {
                throw ApiError::badRequest('Request not found or already reviewed.', 'bad_deposit');
            }
            Db::run(
                'UPDATE coin_deposit_requests SET status = \'rejected\', admin_note = ?, reviewed_at = NOW() WHERE id = ?',
                [trim($note) === '' ? null : trim($note), $id]
            );
            $msg = trim($note) !== '' ? trim($note) : 'Your manual coin add request was rejected.';
            Push::notifyUser((int) $r['user_id'], 'deposit_rejected', 'Coin add rejected', $msg);
        });
    }

    /** @return list<array<string,mixed>> */
    public static function activityItems(int $userId, int $limit): array
    {
        $out = [];
        foreach (Db::all(
            'SELECT * FROM coin_deposit_requests WHERE user_id = ? ORDER BY id DESC LIMIT ' . max(1, min(100, $limit)),
            [$userId]
        ) as $r) {
            $out[] = ['kind' => 'deposit', 'at' => strtotime((string) $r['created_at']) * 1000] + self::publicRow($r);
        }
        return $out;
    }

    /** @param array<string,mixed> $r */
    public static function publicRow(array $r): array
    {
        $prov = (string) $r['provider'];
        return [
            'id' => (int) $r['id'],
            'bdt' => (int) $r['bdt_amount'],
            'coins' => (int) $r['coins'],
            'provider' => $prov,
            'providerLabel' => self::PROVIDERS[$prov] ?? $prov,
            'trxId' => (string) $r['trx_id'],
            'payerNumber' => self::maskPhone((string) $r['payer_number']),
            'status' => $r['status'],
            'adminNote' => $r['admin_note'],
            'createdAt' => strtotime((string) $r['created_at']) * 1000,
            'reviewedAt' => $r['reviewed_at'] !== null ? strtotime((string) $r['reviewed_at']) * 1000 : null,
        ];
    }

    public static function walletLabel(string $reason): ?string
    {
        if (str_starts_with($reason, 'deposit:')) {
            return 'Manual deposit approved';
        }
        return null;
    }

    private static function formatAgentNumber(string $raw): string
    {
        $d = preg_replace('/\D/', '', $raw) ?? '';
        if (strlen($d) === 11 && str_starts_with($d, '0')) {
            return $d;
        }
        if (strlen($d) === 10 && str_starts_with($d, '1')) {
            return '0' . $d;
        }
        return $raw;
    }

    private static function normalizeTrx(string $raw): string
    {
        $t = strtoupper(preg_replace('/\s+/', '', trim($raw)) ?? '');
        if (strlen($t) < 6 || strlen($t) > 24 || preg_match('/^[A-Z0-9]+$/', $t) !== 1) {
            throw ApiError::badRequest('Enter a valid TrxID from your SMS (6–24 letters/numbers).', 'bad_trx');
        }
        return $t;
    }

    /** @throws ApiError */
    private static function normalizePayer(string $raw): string
    {
        $d = preg_replace('/\D/', '', trim($raw)) ?? '';
        if (preg_match('/^1[3-9]\d{8}$/', $d) === 1) {
            return '0' . $d;
        }
        if (preg_match('/^01[3-9]\d{8}$/', $d) === 1) {
            return $d;
        }
        throw ApiError::badRequest('Enter the mobile number you sent payment from.', 'bad_phone');
    }

    private static function maskPhone(string $n): string
    {
        $d = preg_replace('/\D/', '', $n) ?? '';
        if (strlen($d) <= 4) {
            return $d;
        }
        return str_repeat('*', max(0, strlen($d) - 4)) . substr($d, -4);
    }

    /** @param array<string,mixed> $raw */
    private static function normalize(array $raw): array
    {
        return [
            'enabled' => (bool) ($raw['enabled'] ?? true),
            'minBdt' => max(10, min(1_000_000, (int) ($raw['minBdt'] ?? 100))),
            'maxBdt' => max(10, min(10_000_000, (int) ($raw['maxBdt'] ?? 50000))),
            'coinPerBdt' => max(1, min(1000, (int) ($raw['coinPerBdt'] ?? 1))),
            'maxPendingPerUser' => max(1, min(20, (int) ($raw['maxPendingPerUser'] ?? 3))),
            'bkashNumber' => trim((string) ($raw['bkashNumber'] ?? '')),
            'nagadNumber' => trim((string) ($raw['nagadNumber'] ?? '')),
            'rocketNumber' => trim((string) ($raw['rocketNumber'] ?? '')),
            'paymentType' => in_array($raw['paymentType'] ?? '', ['personal', 'agent', 'merchant'], true)
                ? (string) $raw['paymentType']
                : 'personal',
        ];
    }
}
