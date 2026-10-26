<?php
declare(strict_types=1);

namespace App;

/** Sends forgot-password OTP SMS (never used for sign-up). */
final class Sms
{
    public static function sendOtp(string $phoneNormalized, string $code): void
    {
        $message = OtpSms::message($code);
        self::appendSmsLog($phoneNormalized, $code, $message);
        self::deliverGateway($phoneNormalized, $message);
    }

    /** Admin test: send one SMS without touching password_resets. */
    public static function sendTest(string $phoneNormalized): void
    {
        $code = OtpSms::generateCode();
        $message = OtpSms::message($code);
        self::appendSmsLog($phoneNormalized, $code, $message);
        self::deliverGateway($phoneNormalized, $message);
    }

    /** @return array{at: string, ok: bool, msg: string}|null */
    public static function lastResult(): ?array
    {
        $row = Db::one("SELECT v FROM settings WHERE k = 'otp_sms_last'");
        if ($row === null) {
            return null;
        }
        $j = json_decode((string) $row['v'], true);
        return is_array($j) ? $j : null;
    }

    private static function remember(bool $ok, string $msg): void
    {
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('otp_sms_last', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode(['at' => date('c'), 'ok' => $ok, 'msg' => $msg], JSON_UNESCAPED_UNICODE)]
        );
    }

    private static function appendSmsLog(string $phoneNormalized, string $code, string $message): void
    {
        $log = Config::get('SMS_LOG');
        if ($log === '') {
            return;
        }
        file_put_contents(
            $log,
            Phone::display($phoneNormalized) . "\nOTP code is $code\n$message\n---\n",
            FILE_APPEND | LOCK_EX
        );
    }

    private static function deliverGateway(string $phoneNormalized, string $message): void
    {
        $c = OtpSms::config();
        if ($c['delivery'] === 'http' && $c['httpUrl'] !== '') {
            self::httpGateway($c, $phoneNormalized, $message);
            return;
        }
        error_log('[PikoPe SMS] ' . Phone::display($phoneNormalized) . ' — ' . $message);
        if (Config::get('SMS_LOG') !== '') {
            self::remember(true, 'Wrote OTP to SMS_LOG (no live gateway).');
            return;
        }
        self::remember(false, 'Delivery is Log only — SMS was not sent to the phone.');
        throw ApiError::conflict(
            'SMS gateway is not live. Admin → Settings → SMS OTP: set Delivery to Live HTTP SMS gateway, paste API key, Save, then Send test OTP.',
            'sms_not_configured'
        );
    }

    /** @param array<string,mixed> $c */
    private static function httpGateway(array $c, string $phoneNormalized, string $message): void
    {
        $key = (string) $c['httpApiKey'];
        $sender = (string) ($c['httpSenderId'] ?? '');
        $local = '0' . substr($phoneNormalized, 3);
        $plain = [
            '{phone}' => $phoneNormalized,
            '{phone_local}' => $local,
            '{message}' => $message,
            '{api_key}' => $key,
            '{sender_id}' => $sender,
        ];
        $query = [
            '{phone}' => rawurlencode($phoneNormalized),
            '{phone_local}' => rawurlencode($local),
            '{message}' => rawurlencode($message),
            '{api_key}' => rawurlencode($key),
            '{sender_id}' => rawurlencode($sender),
        ];

        $method = (string) ($c['httpMethod'] ?? 'post_json');
        $url = str_replace(array_keys($query), array_values($query), (string) $c['httpUrl']);

        $headers = [];
        $postFields = null;
        $useGet = $method === 'get';

        if (!$useGet) {
            $body = str_replace(array_keys($plain), array_values($plain), (string) $c['httpBodyTemplate']);
            if ($method === 'post_form') {
                $headers[] = 'Content-Type: application/x-www-form-urlencoded';
                $postFields = $body;
            } else {
                $headers[] = 'Content-Type: application/json';
                $postFields = $body;
            }
        }
        if ($key !== '' && ($method === 'post_json' || $method === 'post_form')) {
            $headers[] = 'Authorization: Bearer ' . $key;
        }

        $ch = curl_init($url);
        $opts = [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_TIMEOUT => 25,
        ];
        if ($useGet) {
            $opts[CURLOPT_HTTPGET] = true;
        } else {
            $opts[CURLOPT_POST] = true;
            $opts[CURLOPT_POSTFIELDS] = $postFields;
        }
        curl_setopt_array($ch, $opts);
        $raw = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlErr = curl_error($ch);
        curl_close($ch);

        if ($raw === false || $status < 200 || $status >= 300) {
            $err = $curlErr !== '' ? $curlErr : "HTTP $status body=" . substr((string) $raw, 0, 200);
            error_log("[PikoPe SMS] gateway failed ($err); " . Phone::display($phoneNormalized) . ' — ' . $message);
            self::remember(false, $err);
            throw ApiError::conflict('Could not send OTP SMS. Check Admin → SMS OTP (API key, gateway, test send).', 'sms_failed');
        }

        $json = json_decode((string) $raw, true);
        $reject = self::gatewayRejected(is_array($json) ? $json : null);
        if ($reject !== null) {
            error_log("[PikoPe SMS] gateway rejected ($reject); " . Phone::display($phoneNormalized));
            self::remember(false, $reject);
            throw ApiError::conflict('SMS provider refused the OTP: ' . $reject, 'sms_failed');
        }
        self::remember(true, 'Gateway HTTP ' . $status);
    }

    /** @param array<string,mixed>|null $json */
    private static function gatewayRejected(?array $json): ?string
    {
        if ($json === null) {
            return null;
        }
        if (array_key_exists('error', $json)) {
            $e = $json['error'];
            if ($e !== 0 && $e !== '0' && $e !== false && $e !== null && $e !== '') {
                return (string) ($json['msg'] ?? $json['message'] ?? $json['error_message'] ?? "error=$e");
            }
        }
        if (array_key_exists('success', $json) && $json['success'] === false) {
            return (string) ($json['message'] ?? $json['msg'] ?? 'success=false');
        }
        $status = strtolower((string) ($json['status'] ?? ''));
        if (in_array($status, ['fail', 'failed', 'error'], true)) {
            return (string) ($json['message'] ?? $json['msg'] ?? $status);
        }
        return null;
    }
}
