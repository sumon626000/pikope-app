<?php
declare(strict_types=1);

namespace App;

/** Sends forgot-password OTP SMS (never used for sign-up). */
final class Sms
{
    public static function sendOtp(string $phoneNormalized, string $code): void
    {
        $message = OtpSms::message($code);
        $log = Config::get('SMS_LOG');
        if ($log !== '') {
            file_put_contents(
                $log,
                Phone::display($phoneNormalized) . "\nOTP code is $code\n$message\n---\n",
                FILE_APPEND | LOCK_EX
            );
            return;
        }

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
        $body = str_replace(
            ['{phone}', '{message}'],
            [$phoneNormalized, $message],
            (string) $c['httpBodyTemplate']
        );
        $headers = ['Content-Type: application/json'];
        $key = (string) $c['httpApiKey'];
        if ($key !== '') {
            $headers[] = 'Authorization: Bearer ' . $key;
        }
        $ch = curl_init((string) $c['httpUrl']);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_POSTFIELDS => $body,
            CURLOPT_TIMEOUT => 20,
        ]);
        $raw = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        if ($raw === false || $status < 200 || $status >= 300) {
            $err = curl_error($ch) ?: "HTTP $status";
            curl_close($ch);
            error_log("[PikoPe SMS] gateway failed ($err); OTP for $phoneNormalized: logged only");
            error_log('[PikoPe SMS] ' . Phone::display($phoneNormalized) . ' — ' . $message);
            return;
        }
        curl_close($ch);
    }
}
