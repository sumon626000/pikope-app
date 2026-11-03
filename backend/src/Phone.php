<?php
declare(strict_types=1);

namespace App;

/** Mobile numbers stored as digits only (E.164 without +). Bangladesh + international. */
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
        if (preg_match('/^8801[3-9]\d{8}$/', $d)) {
            return $d;
        }
        if (strlen($d) >= 10 && strlen($d) <= 15 && preg_match('/^[1-9]\d+$/', $d)) {
            return $d;
        }
        throw ApiError::badRequest('Use a valid mobile number with country code', 'bad_phone');
    }

    public static function display(string $normalized): string
    {
        if (preg_match('/^8801[3-9]\d{8}$/', $normalized)) {
            return '+880 ' . substr($normalized, 3);
        }
        return '+' . $normalized;
    }
}
