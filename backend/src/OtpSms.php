<?php
declare(strict_types=1);

namespace App;

/** Admin settings for forgot-password SMS OTP (sign-up does not use OTP). */
final class OtpSms
{
    public const DEFAULTS = [
        'enabled' => true,
        'otpDigits' => 6,
        'validMinutes' => 15,
        'maxPerPhonePerHour' => 3,
        'maxPerIpPerHour' => 10,
        /** log = error log only; http = call gateway URL */
        'delivery' => 'log',
        'messageTemplate' => 'PikoPe password reset: {code}. Valid {minutes} minutes.',
        /** custom | alpha | gotisms | qsms — UI hint only; gateway fields are what run. */
        'providerPreset' => 'custom',
        /** get | post_json | post_form */
        'httpMethod' => 'post_json',
        'httpUrl' => '',
        'httpApiKey' => '',
        'httpSenderId' => '',
        'httpBodyTemplate' => '{"to":"{phone}","text":"{message}"}',
    ];

    /** @var array<string,mixed>|null */
    private static ?array $config = null;

    /** @return array<string, array<string, string>> */
    public static function providerPresets(): array
    {
        return [
            'custom' => [
                'label' => 'Custom (set URL & body yourself)',
                'httpMethod' => 'post_json',
                'httpUrl' => '',
                'httpBodyTemplate' => '{"to":"{phone}","text":"{message}"}',
            ],
            'alpha' => [
                'label' => 'Alpha SMS (sms.bd / api.sms.net.bd)',
                'httpMethod' => 'get',
                'httpUrl' => 'https://api.sms.net.bd/sendsms?api_key={api_key}&msg={message}&to={phone}',
                'httpBodyTemplate' => '',
            ],
            'gotisms' => [
                'label' => 'GotiSMS (OTP REST)',
                'httpMethod' => 'post_json',
                'httpUrl' => 'https://api.gotisms.com/api/messages/send',
                'httpBodyTemplate' => '{"recipients":["{phone_local}"],"senderId":"{sender_id}","message":"{message}","category":"otp"}',
            ],
            'qsms' => [
                'label' => 'Qolek SMS (qsms.com.bd)',
                'httpMethod' => 'post_json',
                'httpUrl' => 'https://api.qsms.com.bd/v1/sms/send',
                'httpBodyTemplate' => '{"recipient":"+{phone}","sender_id":"{sender_id}","type":"plain","message":"{message}"}',
            ],
        ];
    }

    /** @return array<string,mixed> */
    public static function config(): array
    {
        if (self::$config !== null) {
            return self::$config;
        }
        $row = Db::one("SELECT v FROM settings WHERE k = 'otp_sms'");
        $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
        $merged = array_merge(self::DEFAULTS, array_intersect_key($saved, self::DEFAULTS));
        self::$config = self::normalize($merged);
        return self::$config;
    }

    /** @param array<string,mixed> $raw */
    public static function save(array $raw): void
    {
        Db::run(
            "INSERT INTO settings (k, v) VALUES ('otp_sms', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)",
            [json_encode(self::normalize($raw))]
        );
        self::$config = null;
    }

    public static function generateCode(): string
    {
        $digits = (int) self::config()['otpDigits'];
        $max = 10 ** $digits - 1;
        return str_pad((string) random_int(0, $max), $digits, '0', STR_PAD_LEFT);
    }

    public static function message(string $code): string
    {
        $c = self::config();
        $mins = (int) $c['validMinutes'];
        return str_replace(['{code}', '{minutes}'], [$code, (string) $mins], (string) $c['messageTemplate']);
    }

    /** @param array<string,mixed> $raw */
    private static function normalize(array $raw): array
    {
        $digits = max(4, min(8, (int) ($raw['otpDigits'] ?? 6)));
        $mins = max(5, min(60, (int) ($raw['validMinutes'] ?? 15)));
        $delivery = (string) ($raw['delivery'] ?? 'log');
        if ($delivery !== 'http') {
            $delivery = 'log';
        }
        $method = (string) ($raw['httpMethod'] ?? 'post_json');
        if (!in_array($method, ['get', 'post_json', 'post_form'], true)) {
            $method = 'post_json';
        }
        $preset = (string) ($raw['providerPreset'] ?? 'custom');
        if (!array_key_exists($preset, self::providerPresets())) {
            $preset = 'custom';
        }
        $tpl = trim((string) ($raw['messageTemplate'] ?? self::DEFAULTS['messageTemplate']));
        if ($tpl === '' || !str_contains($tpl, '{code}')) {
            $tpl = self::DEFAULTS['messageTemplate'];
        }
        $bodyTpl = trim((string) ($raw['httpBodyTemplate'] ?? self::DEFAULTS['httpBodyTemplate']));
        return [
            'enabled' => (bool) ($raw['enabled'] ?? true),
            'otpDigits' => $digits,
            'validMinutes' => $mins,
            'maxPerPhonePerHour' => max(1, min(20, (int) ($raw['maxPerPhonePerHour'] ?? 3))),
            'maxPerIpPerHour' => max(1, min(100, (int) ($raw['maxPerIpPerHour'] ?? 10))),
            'delivery' => $delivery,
            'messageTemplate' => $tpl,
            'providerPreset' => $preset,
            'httpMethod' => $method,
            'httpUrl' => trim((string) ($raw['httpUrl'] ?? '')),
            'httpApiKey' => trim((string) ($raw['httpApiKey'] ?? '')),
            'httpSenderId' => trim((string) ($raw['httpSenderId'] ?? '')),
            'httpBodyTemplate' => $bodyTpl,
        ];
    }
}
