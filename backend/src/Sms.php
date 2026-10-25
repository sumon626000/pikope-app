<?php
declare(strict_types=1);

namespace App;

/** Sends forgot-password OTP SMS (never used for sign-up). */
final class Sms
{
    public static function sendOtp(string $phoneNormalized, string $code): void
    {
        $message = OtpSms::message($code);
        if (self::appendSmsLog($phoneNormalized, $code, $message)) {
            return;
        }
        self::deliverGateway($phoneNormalized, $message);
    }

    /** Admin test: send one SMS without touching password_resets. */
    public static function sendTest(string $phoneNormalized): void
    {
        $code = OtpSms::generateCode();
        $message = OtpSms::message($code);
        if (self::appendSmsLog($phoneNormalized, $code, $message)) {
            return;
        }
        self::deliverGateway($phoneNormalized, $message);
    }

    private static function appendSmsLog(string $phoneNormalized, string $code, string $message): bool
    {
        $log = Config::get('SMS_LOG');
        if ($log === '') {
            return false;
        }
        file_put_contents(
            $log,
            Phone::display($phoneNormalized) . "\nOTP code is $code\n$message\n---\n",
            FILE_APPEND | LOCK_EX
        );
        return true;
    }

    private static function deliverGateway(string $phoneNormalized, string $message): void
    {
        $c = OtpSms::config();
        if ($c['delivery'] === 'http' && $c['httpUrl'] !== '') {
            self::httpGateway($c, $phoneNormalized, $message);
            return;
        }
        error_log('[PikoPe SMS] ' . Phone::display($phoneNormalized) . ' — ' . $message);
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
        if ($raw === false || $status < 200 || $status >= 300) {
            $err = curl_error($ch) ?: "HTTP $status body=" . substr((string) $raw, 0, 200);
            curl_close($ch);
            error_log("[PikoPe SMS] gateway failed ($err); " . Phone::display($phoneNormalized) . ' — ' . $message);
            return;
        }
        curl_close($ch);
    }
}
