<?php
declare(strict_types=1);

namespace App;

/** Crypto coin add via NOWPayments hosted invoice. API key + IPN secret stay on server. */
final class NowPayments
{
    private const API = 'https://api.nowpayments.io/v1';

    public const DEFAULTS = [
        'enabled' => false,
        'apiKey' => '',
        'ipnSecret' => '',
        'priceCurrency' => 'usd',
        /** BDT per 1 USD when priceCurrency is usd (pack price is BDT). */
        'bdtPerUsd' => 110,
    ];

    /** @var array<string,mixed>|null */
    private static ?array $config = null;

    public static function ensureTable(): void
    {
        Db::run(
            'CREATE TABLE IF NOT EXISTS nowpayments_deposits (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                user_id BIGINT UNSIGNED NOT NULL,
                bdt_amount INT NOT NULL,
                coins INT NOT NULL,
                price_amount DECIMAL(12,4) NOT NULL DEFAULT 0,
                price_currency VARCHAR(8) NOT NULL DEFAULT \'usd\',
                invoice_id VARCHAR(64) NULL,
                payment_id VARCHAR(64) NULL,
                payment_status VARCHAR(32) NOT NULL DEFAULT \'pending\',
                credited TINYINT(1) NOT NULL DEFAULT 0,
                pack_id VARCHAR(32) NULL,
                base_coins INT NOT NULL DEFAULT 0,
                bonus_coins INT NOT NULL DEFAULT 0,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                completed_at DATETIME NULL,
                KEY idx_np_user (user_id, created_at),
                KEY idx_np_invoice (invoice_id),
                KEY idx_np_payment (payment_id),
                CONSTRAINT fk_np_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
    }

    /** @return array<string,mixed> */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'nowpayments'");
        $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
        self::$config = self::normalize(array_merge(self::DEFAULTS, array_intersect_key($saved, self::DEFAULTS)));
        return self::$config;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('nowpayments', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode(self::normalize($raw))]
        );
        self::$config = null;
    }

    public static function publicEnabled(): bool
    {
        $c = self::config();
        return (bool) $c['enabled'] && trim((string) $c['apiKey']) !== '';
    }

    public static function maskedApiKey(): string
    {
        $k = (string) self::config()['apiKey'];
        if ($k === '') {
            return '(none)';
        }
        $n = strlen($k);
        if ($n <= 8) {
            return str_repeat('*', $n);
        }
        return substr($k, 0, 4) . str_repeat('*', max(4, $n - 8)) . substr($k, -4);
    }

    /** @return array{appUrl:string,webhookUrl:string,returnUrlExample:string} */
    public static function adminUrls(): array
    {
        $base = rtrim(Config::get('APP_URL', ''), '/');
        return [
            'appUrl' => $base,
            'webhookUrl' => $base === '' ? '' : $base . '/webhooks/nowpayments',
            'returnUrlExample' => $base === '' ? '' : $base . '/deposit/nowpayments/return?deposit=ID&status=success',
        ];
    }

    /** @return array<string,mixed> */
    public static function start(int $userId, int $bdt, ?string $packId = null, int $qty = 1): array
    {
        if (!self::publicEnabled()) {
            throw ApiError::badRequest('Crypto pay is not available yet.', 'nowpayments_disabled');
        }
        $dep = CoinDeposit::config();
        $min = (int) $dep['minBdt'];
        $max = (int) $dep['maxBdt'];
        if ($bdt < $min || $bdt > $max) {
            throw ApiError::badRequest("Amount must be between $min and $max BDT.", 'bad_amount');
        }
        $c = self::config();
        $credit = CoinDeposit::creditCoinsForBdt($bdt, $packId, $qty);
        $currency = strtolower((string) $c['priceCurrency']);
        if ($currency === 'bdt') {
            $priceAmount = (float) $bdt;
        } else {
            // 1 coin ≈ 1 BDT; invoice USD = pack BDT ÷ live/manual market rate.
            $rate = max(1.0, UsdMarketRate::bdtPerUsd());
            $priceAmount = round($bdt / $rate, 2);
            $currency = 'usd';
        }
        if ($priceAmount < 0.01) {
            throw ApiError::badRequest('Amount too small for crypto checkout.', 'bad_amount');
        }

        $base = rtrim(Config::get('APP_URL', ''), '/');
        if ($base === '') {
            throw ApiError::badRequest('APP_URL is not configured on the server.', 'misconfigured');
        }

        self::ensureTable();
        Db::run(
            'INSERT INTO nowpayments_deposits
             (user_id, bdt_amount, coins, price_amount, price_currency, pack_id, base_coins, bonus_coins)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $userId,
                $bdt,
                $credit['coins'],
                $priceAmount,
                $currency,
                $credit['packId'],
                $credit['base'],
                $credit['bonus'],
            ]
        );
        $depositId = Db::lastId();
        $orderId = 'np-' . $depositId;
        $success = $base . '/deposit/nowpayments/return?deposit=' . $depositId . '&status=success';
        $cancel = $base . '/deposit/nowpayments/return?deposit=' . $depositId . '&status=cancel';
        $ipn = $base . '/webhooks/nowpayments';

        $invoice = self::apiPost('/invoice', [
            'price_amount' => $priceAmount,
            'price_currency' => $currency,
            'order_id' => $orderId,
            'order_description' => 'PikoPe ' . $credit['coins'] . ' coins',
            'ipn_callback_url' => $ipn,
            'success_url' => $success,
            'cancel_url' => $cancel,
        ]);
        $invoiceId = (string) ($invoice['id'] ?? '');
        $invoiceUrl = (string) ($invoice['invoice_url'] ?? '');
        if ($invoiceId === '' || $invoiceUrl === '') {
            throw ApiError::badRequest('NOWPayments did not return an invoice URL.', 'nowpayments_error');
        }
        Db::run(
            'UPDATE nowpayments_deposits SET invoice_id = ?, payment_status = ? WHERE id = ?',
            [$invoiceId, 'waiting', $depositId]
        );

        return [
            'depositId' => $depositId,
            'checkoutUrl' => $invoiceUrl,
            'coins' => $credit['coins'],
            'bdt' => $bdt,
            'priceAmount' => $priceAmount,
            'priceCurrency' => $currency,
        ];
    }

    /** @return array<string,mixed> */
    public static function finish(int $userId, int $depositId): array
    {
        self::ensureTable();
        return Db::transaction(static function () use ($userId, $depositId): array {
            $row = Db::one('SELECT * FROM nowpayments_deposits WHERE id = ? FOR UPDATE', [$depositId]);
            if ($row === null || (int) $row['user_id'] !== $userId) {
                throw ApiError::notFound('Deposit not found');
            }
            if ((int) $row['credited'] === 1) {
                return [
                    'credited' => true,
                    'coins' => (int) $row['coins'],
                    'user' => Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$userId])),
                ];
            }
            throw ApiError::conflict('Payment not confirmed yet. Wait a moment and try again.', 'not_paid');
        });
    }

    /** @param array<string,mixed> $body */
    public static function webhook(array $body): array
    {
        $raw = file_get_contents('php://input') ?: '';
        if (!self::verifyIpn($raw, (string) ($_SERVER['HTTP_X_NOWPAYMENTS_SIG'] ?? ''))) {
            throw ApiError::forbidden('Bad NOWPayments signature', 'bad_signature');
        }
        $data = json_decode($raw, true);
        if (!is_array($data)) {
            $data = $body;
        }
        $orderId = (string) ($data['order_id'] ?? '');
        $status = strtolower((string) ($data['payment_status'] ?? $data['status'] ?? ''));
        $paymentId = (string) ($data['payment_id'] ?? $data['id'] ?? '');
        if (!preg_match('/^np-(\d+)$/', $orderId, $m)) {
            return ['ok' => true, 'ignored' => 'bad_order'];
        }
        $depositId = (int) $m[1];
        self::ensureTable();

        return Db::transaction(static function () use ($depositId, $status, $paymentId): array {
            $row = Db::one('SELECT * FROM nowpayments_deposits WHERE id = ? FOR UPDATE', [$depositId]);
            if ($row === null) {
                return ['ok' => true, 'ignored' => 'missing'];
            }
            Db::run(
                'UPDATE nowpayments_deposits SET payment_status = ?, payment_id = COALESCE(NULLIF(?, \'\'), payment_id) WHERE id = ?',
                [$status !== '' ? $status : $row['payment_status'], $paymentId, $depositId]
            );
            if ((int) $row['credited'] === 1) {
                return ['ok' => true, 'already' => true];
            }
            if (!in_array($status, ['finished', 'confirmed'], true)) {
                return ['ok' => true, 'pending' => $status];
            }
            $uid = (int) $row['user_id'];
            $coins = (int) $row['coins'];
            $reason = 'nowpay:' . $depositId;
            $exists = Db::one('SELECT id FROM wallet_tx WHERE user_id = ? AND reason = ?', [$uid, $reason]);
            if ($exists === null) {
                Economy::move($uid, $coins, $reason);
            }
            Db::run(
                'UPDATE nowpayments_deposits SET credited = 1, completed_at = NOW(), payment_status = ? WHERE id = ?',
                [$status, $depositId]
            );
            try {
                Push::notifyUser(
                    $uid,
                    'deposit_approved',
                    'Coins added',
                    '+' . $coins . ' Pico coin (crypto).',
                    [],
                    'nowpay:' . $depositId
                );
            } catch (\Throwable $e) {
                error_log('[nowpayments] push: ' . $e->getMessage());
            }
            return ['ok' => true, 'credited' => true];
        });
    }

    public static function returnHtml(): never
    {
        $deposit = (int) ($_GET['deposit'] ?? 0);
        $status = (string) ($_GET['status'] ?? '');
        $ok = $status === 'success';
        header('Content-Type: text/html; charset=utf-8');
        echo '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">',
            '<title>PikoPe Crypto</title><style>body{font-family:system-ui;background:#0b1020;color:#e9ecf5;display:flex;',
            'min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px;text-align:center}</style></head><body>',
            '<div><h1>', $ok ? 'Payment submitted' : 'Checkout closed', '</h1>',
            '<p>', $ok
                ? 'Return to the app — coins appear after confirmation (deposit #' . (int) $deposit . ').'
                : 'You can close this page and try again in the app.',
            '</p></div></body></html>';
        exit;
    }

    /** @return list<array<string,mixed>> */
    public static function listRecent(int $limit = 80): array
    {
        self::ensureTable();
        $limit = max(1, min(200, $limit));
        return Db::all(
            'SELECT d.*, u.display_name FROM nowpayments_deposits d
             JOIN users u ON u.id = d.user_id
             ORDER BY d.id DESC LIMIT ' . $limit
        );
    }

    private static function verifyIpn(string $raw, string $sig): bool
    {
        $secret = trim((string) self::config()['ipnSecret']);
        if ($secret === '' || $sig === '') {
            // If IPN secret not set yet, reject (safer than accepting unsigned).
            return false;
        }
        $data = json_decode($raw, true);
        if (!is_array($data)) {
            return false;
        }
        self::ksortRecursive($data);
        $sorted = json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        if ($sorted === false) {
            return false;
        }
        $hmac = hash_hmac('sha512', $sorted, $secret);
        return hash_equals($hmac, $sig);
    }

    /** @param array<mixed> $arr */
    private static function ksortRecursive(array &$arr): void
    {
        ksort($arr);
        foreach ($arr as &$v) {
            if (is_array($v)) {
                self::ksortRecursive($v);
            }
        }
    }

    /** @param array<string,mixed> $payload @return array<string,mixed> */
    private static function apiPost(string $path, array $payload): array
    {
        $key = trim((string) self::config()['apiKey']);
        $ch = curl_init(self::API . $path);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => json_encode($payload),
            CURLOPT_HTTPHEADER => [
                'x-api-key: ' . $key,
                'Content-Type: application/json',
            ],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 25,
            CURLOPT_SSL_VERIFYPEER => true,
        ]);
        $body = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err = curl_error($ch);
        curl_close($ch);
        if ($body === false || $err !== '') {
            throw ApiError::badRequest('NOWPayments request failed.', 'nowpayments_error');
        }
        $data = json_decode($body, true);
        if (!is_array($data) || $code >= 400) {
            $msg = is_array($data) ? (string) ($data['message'] ?? $data['error'] ?? 'NOWPayments error') : 'NOWPayments error';
            throw ApiError::badRequest($msg, 'nowpayments_error');
        }
        return $data;
    }

    /** @param array<string,mixed> $raw */
    private static function normalize(array $raw): array
    {
        $cur = strtolower(trim((string) ($raw['priceCurrency'] ?? 'usd')));
        if ($cur !== 'bdt') {
            $cur = 'usd';
        }
        return [
            'enabled' => (bool) ($raw['enabled'] ?? false),
            'apiKey' => trim((string) ($raw['apiKey'] ?? '')),
            'ipnSecret' => trim((string) ($raw['ipnSecret'] ?? '')),
            'priceCurrency' => $cur,
            'bdtPerUsd' => max(1.0, min(500.0, (float) ($raw['bdtPerUsd'] ?? 110))),
        ];
    }
}
