<?php
declare(strict_types=1);

namespace App;

/** Fixed-window throttling backed by the `rate_limits` table. */
final class RateLimit
{
    /** Counts one hit; refuses with 429 once $limit is passed within the window. */
    public static function hit(string $bucket, int $limit, int $windowSeconds): void
    {
        $limit *= max(1, Config::int('RATE_LIMIT_FACTOR', 1));
        $window = intdiv(time(), $windowSeconds) * $windowSeconds;
        Db::run(
            'INSERT INTO rate_limits (bucket, window_start, hits) VALUES (?, ?, 1)
             ON DUPLICATE KEY UPDATE hits = hits + 1',
            [substr($bucket, 0, 120), $window]
        );
        $hits = (int) Db::one('SELECT hits FROM rate_limits WHERE bucket = ? AND window_start = ?',
            [substr($bucket, 0, 120), $window])['hits'];
        if ($hits > $limit) {
            throw new ApiError(429, 'too_many_requests', 'Too many requests. Try again later.');
        }
    }

    /** Cloudflare's published edge ranges (https://www.cloudflare.com/ips/). */
    private const CLOUDFLARE = [
        '173.245.48.0/20', '103.21.244.0/22', '103.22.200.0/22', '103.31.4.0/22', '141.101.64.0/18',
        '108.162.192.0/18', '190.93.240.0/20', '188.114.96.0/20', '197.234.240.0/22', '198.41.128.0/17',
        '162.158.0.0/15', '104.16.0.0/13', '104.24.0.0/14', '172.64.0.0/13', '131.0.72.0/22',
        '2400:cb00::/32', '2606:4700::/32', '2803:f800::/32', '2405:b500::/32', '2405:8100::/32',
        '2a06:98c0::/29', '2c0f:f248::/32',
    ];

    /**
     * The caller's address. Behind Cloudflare the connection comes from one of
     * its edges, which names the real visitor in CF-Connecting-IP; that header
     * is believed only when the connection really is from Cloudflare.
     */
    public static function ip(): string
    {
        $peer = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
        $visitor = $_SERVER['HTTP_CF_CONNECTING_IP'] ?? '';
        if ($visitor !== '' && filter_var($visitor, FILTER_VALIDATE_IP) !== false && self::fromCloudflare($peer)) {
            return $visitor;
        }
        return $peer;
    }

    private static function fromCloudflare(string $ip): bool
    {
        $addr = @inet_pton($ip);
        if ($addr === false) {
            return false;
        }
        foreach (self::CLOUDFLARE as $range) {
            [$net, $bits] = explode('/', $range);
            $net = inet_pton($net);
            if (strlen($net) !== strlen($addr)) {
                continue;
            }
            $bits = (int) $bits;
            $bytes = intdiv($bits, 8);
            if (substr($addr, 0, $bytes) !== substr($net, 0, $bytes)) {
                continue;
            }
            $rest = $bits % 8;
            if ($rest === 0 || ((ord($addr[$bytes]) ^ ord($net[$bytes])) >> (8 - $rest)) === 0) {
                return true;
            }
        }
        return false;
    }
}
