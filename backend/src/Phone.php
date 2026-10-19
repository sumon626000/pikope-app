<?php
declare(strict_types=1);

namespace App;

/** Bangladesh mobile numbers only, stored as 8801XXXXXXXXX (13 digits). */
final class Phone
{
    /** @throws ApiError */
    public static function normalize(string $raw): string
    {
        $d = preg_replace('/\D/', '', trim($raw)) ?? '';
        if ($d === '') {
            throw ApiError::badRequest('Enter your mobile number', 'bad_phone');
        }
        if (str_starts_with($d, '0')) {
            $d = '88' . $d;
        }
        if (str_starts_with($d, '1') && strlen($d) === 10) {
            $d = '880' . $d;
        }
        if (str_starts_with($d, '880') && strlen($d) === 12) {
            $d = '880' . substr($d, 3);
        }
        if (!preg_match('/^8801[3-9]\d{8}$/', $d)) {
            throw ApiError::badRequest('Use a valid Bangladesh mobile number (+880)', 'bad_phone');
        }
        return $d;
    }

    public static function display(string $normalized): string
    {
        return '+880 ' . substr($normalized, 3);
    }
}
