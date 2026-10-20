<?php
declare(strict_types=1);

namespace App;

/** Auto coin add via ZiniPay hosted checkout (WebView in the app). API key stays on server. */
final class ZiniPay
{
    private const API = 'https://api.zinipay.com';

    public const DEFAULTS = [
        'enabled' => false,
        'apiKey' => '',
    ];

    /** @var array<string,mixed>|null */
    private static ?array $config = null;

    public static function ensureTable(): void
    {
        Db::run(
            'CREATE TABLE IF NOT EXISTS zinipay_deposits (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                user_id BIGINT UNSIGNED NOT NULL,
                bdt_amount INT NOT NULL,
                coins INT NOT NULL,
                invoice_id VARCHAR(64) NULL,
                zini_status VARCHAR(24) NOT NULL DEFAULT \'pending\',
                zini_transaction_id VARCHAR(64) NULL,
                credited TINYINT(1) NOT NULL DEFAULT 0,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                completed_at DATETIME NULL,
                KEY idx_zini_user (user_id, created_at),
                KEY idx_zini_invoice (invoice_id),
                CONSTRAINT fk_zini_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
    }

    /** @return array<string,mixed> */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'zinipay'");
        $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
        self::$config = self::normalize(array_merge(self::DEFAULTS, array_intersect_key($saved, self::DEFAULTS)));
        return self::$config;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('zinipay', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode(self::normalize($raw))]
        );
        self::$config = null;
    }

    public static function publicEnabled(): bool
    {
        $c = self::config();
        return (bool) $c['enabled'] && trim((string) $c['apiKey']) !== '';
    }

    /** @return array<string,mixed> */
    public static function start(int $userId, int $bdt): array
    {
        if (!self::publicEnabled()) {
            throw ApiError::badRequest('Auto pay is not available yet.', 'zini_disabled');
        }
        $dep = CoinDeposit::config();
        $min = (int) $dep['minBdt'];
        $max = (int) $dep['maxBdt'];
        if ($bdt < $min || $bdt > $max) {
            throw ApiError::badRequest("Amount must be between $min and $max BDT.", 'bad_amount');
        }
        $rate = max(1, (int) $dep['coinPerBdt']);
        $coins = Promotions::depositCoins($bdt, $rate);
        $user = Db::one('SELECT id, display_name, email FROM users WHERE id = ?', [$userId]);
        if ($user === null) {
            throw ApiError::notFound('User not found');
        }

        self::ensureTable();
        Db::run(
            'INSERT INTO zinipay_deposits (user_id, bdt_amount, coins) VALUES (?, ?, ?)',
            [$userId, $bdt, $coins]
        );
        $depositId = Db::lastId();
        $base = rtrim(Config::get('APP_URL', ''), '/');
        if ($base === '') {
            throw ApiError::badRequest('APP_URL is not configured on the server.', 'misconfigured');
        }
        $redirect = $base . '/deposit/zinipay/return?deposit=' . $depositId . '&status=success';
        $cancel = $base . '/deposit/zinipay/return?deposit=' . $depositId . '&status=cancel';
        $webhook = $base . '/webhooks/zinipay';

        $payload = [
            'cus_name' => (string) $user['display_name'],
            'amount' => $bdt,
            'metadata' => [
                'deposit_id' => $depositId,
                'user_id' => $userId,
            ],
            'redirect_url' => $redirect,
            'cancel_url' => $cancel,
            'webhook_url' => $webhook,
        ];
        $email = trim((string) ($user['email'] ?? ''));
        if ($email !== '' && str_contains($email, '@')) {
            $payload['cus_email'] = $email;
        }

        $created = self::apiPost('/v1/payment/create', $payload);
        $paymentUrl = (string) ($created['payment_url'] ?? '');
        if ($paymentUrl === '') {
            throw ApiError::badRequest('Payment gateway did not return a URL.', 'zini_create_failed');
        }
        $invoiceId = self::invoiceIdFromUrl($paymentUrl);
        Db::run(
            'UPDATE zinipay_deposits SET invoice_id = ? WHERE id = ?',
            [$invoiceId, $depositId]
        );

        return [
            'deposit' => self::publicRow(Db::one('SELECT * FROM zinipay_deposits WHERE id = ?', [$depositId])),
            'paymentUrl' => $paymentUrl,
            'returnPath' => '/deposit/zinipay/return',
        ];
    }

    /** Player returns from WebView — verify with ZiniPay and credit once. */
    public static function finish(int $userId, int $depositId): array
    {
        self::ensureTable();
        return Db::transaction(static function () use ($userId, $depositId): array {
            $row = Db::one('SELECT * FROM zinipay_deposits WHERE id = ? FOR UPDATE', [$depositId]);
            if ($row === null || (int) $row['user_id'] !== $userId) {
                throw ApiError::notFound('Payment session not found.');
            }
            if ((int) $row['credited'] === 1) {
                return [
                    'deposit' => self::publicRow($row),
                    'user' => Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$userId])),
                    'alreadyCredited' => true,
                ];
            }
            $invoiceId = (string) ($row['invoice_id'] ?? '');
            if ($invoiceId === '') {
                throw ApiError::conflict('Payment not started yet.', 'zini_pending');
            }
            $verified = self::verifyInvoice($invoiceId);
            $status = strtoupper((string) ($verified['status'] ?? 'PENDING'));
            Db::run(
                'UPDATE zinipay_deposits SET zini_status = ?, zini_transaction_id = ? WHERE id = ?',
                [$status, $verified['transaction_id'] ?? null, $depositId]
            );
            if ($status !== 'COMPLETED') {
                throw ApiError::conflict('Payment not completed yet.', 'zini_not_paid');
            }
            Economy::move($userId, (int) $row['coins'], 'zinipay:' . $depositId);
            Db::run(
                'UPDATE zinipay_deposits SET credited = 1, completed_at = NOW() WHERE id = ?',
                [$depositId]
            );
            $row = Db::one('SELECT * FROM zinipay_deposits WHERE id = ?', [$depositId]);
            Push::notifyUser($userId, 'deposit_ok', 'Pico coin added', (int) $row['coins'] . ' Pico coin credited.');
            return [
                'deposit' => self::publicRow($row),
                'user' => Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$userId])),
                'alreadyCredited' => false,
            ];
        });
    }

    /** @param array<string,mixed> $body */
    public static function webhook(array $body): array
    {
        if (!self::publicEnabled()) {
            return ['ok' => false];
        }
        $invoiceId = (string) ($body['invoice_id'] ?? $body['invoiceId'] ?? '');
        if ($invoiceId === '') {
            return ['ok' => false, 'reason' => 'no_invoice'];
        }
        self::ensureTable();
        $row = Db::one('SELECT * FROM zinipay_deposits WHERE invoice_id = ?', [$invoiceId]);
        if ($row === null || (int) $row['credited'] === 1) {
            return ['ok' => true];
        }
        try {
            self::finish((int) $row['user_id'], (int) $row['id']);
        } catch (ApiError) {
            // Webhook may arrive before redirect; app will retry finish.
        }
        return ['ok' => true];
    }

    public static function returnHtml(): never
    {
        $deposit = (int) ($_GET['deposit'] ?? 0);
        $status = (string) ($_GET['status'] ?? 'success');
        $title = $status === 'cancel' ? 'Payment cancelled' : 'Payment complete';
        $msg = $status === 'cancel'
            ? 'You can close this and try again in the app.'
            : 'Return to PikoPe — your coin will appear in a moment.';
        header('Content-Type: text/html; charset=utf-8');
        header('Cache-Control: no-store');
        echo '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
            '<title>', htmlspecialchars($title), '</title>',
            '<style>body{font-family:sans-serif;background:#070a18;color:#e9ecf5;text-align:center;padding:48px 24px}',
            'h1{color:#f5c842}p{opacity:.85}</style></head><body>',
            '<h1>', htmlspecialchars($title), '</h1>',
            '<p>', htmlspecialchars($msg), '</p>',
            '<p><small>deposit #', $deposit, '</small></p>',
            '</body></html>';
        exit;
    }

    /** @return array<string,mixed> */
    private static function verifyInvoice(string $invoiceId): array
    {
        $r = self::apiPost('/v1/payment/verify', ['invoice_id' => $invoiceId]);
        if (!is_array($r)) {
            throw ApiError::badRequest('Invalid verify response.', 'zini_verify');
        }
        return $r;
    }

    /** @param array<string,mixed> $payload @return array<string,mixed> */
    private static function apiPost(string $path, array $payload): array
    {
        $key = trim((string) self::config()['apiKey']);
        if ($key === '') {
            throw ApiError::badRequest('ZiniPay API key missing.', 'zini_key');
        }
        $url = self::API . $path;
        $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($json === false) {
            throw ApiError::badRequest('Invalid payment payload.');
        }
        $ch = curl_init($url);
        if ($ch === false) {
            throw ApiError::badRequest('Could not reach payment gateway.');
        }
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $json,
            CURLOPT_HTTPHEADER => [
                'Content-Type: application/json',
                'zini-api-key: ' . $key,
            ],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 30,
        ]);
        $raw = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if (!is_string($raw) || $raw === '') {
            throw ApiError::badRequest('Empty response from payment gateway.', 'zini_http');
        }
        $data = json_decode($raw, true);
        if (!is_array($data)) {
            throw ApiError::badRequest('Invalid JSON from payment gateway.', 'zini_http');
        }
        if ($code >= 400 || ($data['status'] ?? true) === false) {
            $msg = (string) ($data['message'] ?? 'Payment gateway error');
            throw ApiError::badRequest($msg, 'zini_api');
        }
        return $data;
    }

    private static function invoiceIdFromUrl(string $paymentUrl): string
    {
        $path = parse_url($paymentUrl, PHP_URL_PATH);
        if (!is_string($path) || $path === '') {
            return '';
        }
        $parts = array_values(array_filter(explode('/', trim($path, '/'))));
        return $parts === [] ? '' : (string) end($parts);
    }

    /** @param array<string,mixed> $r */
    public static function publicRow(array $r): array
    {
        return [
            'id' => (int) $r['id'],
            'bdt' => (int) $r['bdt_amount'],
            'coins' => (int) $r['coins'],
            'status' => (string) $r['zini_status'],
            'credited' => (bool) $r['credited'],
            'createdAt' => strtotime((string) $r['created_at']) * 1000,
        ];
    }

    /** Copy-paste URLs for ZiniPay dashboard (webhook / redirect domain). */
    public static function adminUrls(): array
    {
        $base = rtrim(Config::get('APP_URL', ''), '/');
        return [
            'appUrl' => $base,
            'webhookUrl' => $base === '' ? '' : $base . '/webhooks/zinipay',
            'returnUrlExample' => $base === '' ? '' : $base . '/deposit/zinipay/return?deposit=1&status=success',
            'apiCreate' => self::API . '/v1/payment/create',
            'apiVerify' => self::API . '/v1/payment/verify',
        ];
    }

    public static function maskedApiKey(): string
    {
        $k = trim((string) self::config()['apiKey']);
        if ($k === '') {
            return '(not set)';
        }
        if (strlen($k) <= 8) {
            return str_repeat('•', strlen($k));
        }
        return substr($k, 0, 4) . str_repeat('•', max(4, strlen($k) - 8)) . substr($k, -4);
    }

    /** @return list<array<string,mixed>> */
    public static function listRecent(int $limit = 60): array
    {
        self::ensureTable();
        $limit = max(1, min(200, $limit));
        $rows = Db::all(
            "SELECT z.*, u.display_name, u.phone
             FROM zinipay_deposits z
             JOIN users u ON u.id = z.user_id
             ORDER BY z.id DESC LIMIT $limit"
        );
        return array_map(static fn (array $r): array => [
            'id' => (int) $r['id'],
            'userId' => (int) $r['user_id'],
            'playerName' => $r['display_name'],
            'phone' => $r['phone'],
            'bdt' => (int) $r['bdt_amount'],
            'coins' => (int) $r['coins'],
            'invoiceId' => $r['invoice_id'],
            'status' => $r['zini_status'],
            'transactionId' => $r['zini_transaction_id'],
            'credited' => (int) $r['credited'] === 1,
            'createdAt' => $r['created_at'],
            'completedAt' => $r['completed_at'],
        ], $rows);
    }

    /** @param array<string,mixed> $raw @return array<string,mixed> */
    private static function normalize(array $raw): array
    {
        return [
            'enabled' => (bool) ($raw['enabled'] ?? false),
            'apiKey' => trim((string) ($raw['apiKey'] ?? '')),
        ];
    }

}
