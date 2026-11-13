<?php
declare(strict_types=1);

namespace App;

/**
 * Live USD→BDT mid-market rate for crypto coin pricing.
 * 1 Piko coin = 1 BDT, so coins per 1 USD ≈ BDT per 1 USD.
 */
final class UsdMarketRate
{
    private const SETTINGS_KEY = 'usd_bdt_market';
    private const CACHE_SECONDS = 21600; // 6h
    private const FALLBACK = 125.0;

    /** @return array{bdtPerUsd:float,coinsPerUsd:int,source:string,updatedAt:string,followMarket:bool} */
    public static function public(): array
    {
        $snap = self::snapshot();
        $coinPerBdt = max(1, (int) (CoinDeposit::config()['coinPerBdt'] ?? 1));
        $bdt = (float) $snap['bdtPerUsd'];
        return [
            'bdtPerUsd' => $bdt,
            'coinsPerUsd' => (int) max(1, round($bdt * $coinPerBdt)),
            'source' => (string) $snap['source'],
            'updatedAt' => (string) $snap['updatedAt'],
            'followMarket' => (bool) $snap['followMarket'],
        ];
    }

    /** Effective BDT per 1 USD used for crypto invoices. */
    public static function bdtPerUsd(): float
    {
        return (float) self::snapshot()['bdtPerUsd'];
    }

    /**
     * Refresh from market when followMarket is on and cache is stale.
     * @return array{bdtPerUsd:float,source:string,updatedAt:string,followMarket:bool,manualBdtPerUsd:float}
     */
    public static function snapshot(bool $forceRefresh = false): array
    {
        $saved = self::load();
        $follow = (bool) ($saved['followMarket'] ?? true);
        $manual = max(1.0, min(500.0, (float) ($saved['manualBdtPerUsd'] ?? self::FALLBACK)));
        $cached = max(1.0, min(500.0, (float) ($saved['bdtPerUsd'] ?? $manual)));
        $source = (string) ($saved['source'] ?? 'manual');
        $updatedAt = (string) ($saved['updatedAt'] ?? '');
        $age = $updatedAt === '' ? PHP_INT_MAX : max(0, time() - strtotime($updatedAt));

        if (!$follow) {
            return [
                'bdtPerUsd' => $manual,
                'source' => 'manual',
                'updatedAt' => $updatedAt !== '' ? $updatedAt : gmdate('c'),
                'followMarket' => false,
                'manualBdtPerUsd' => $manual,
            ];
        }

        if ($forceRefresh || $age >= self::CACHE_SECONDS || $source === 'manual' || $source === '') {
            $fetched = self::fetchMarket();
            if ($fetched !== null) {
                $cached = $fetched['bdtPerUsd'];
                $source = $fetched['source'];
                $updatedAt = gmdate('c');
                self::persist([
                    'followMarket' => true,
                    'manualBdtPerUsd' => $manual,
                    'bdtPerUsd' => $cached,
                    'source' => $source,
                    'updatedAt' => $updatedAt,
                ]);
            } elseif ($updatedAt === '') {
                $cached = $manual;
                $source = 'fallback';
                $updatedAt = gmdate('c');
            }
        }

        return [
            'bdtPerUsd' => $cached,
            'source' => $source,
            'updatedAt' => $updatedAt,
            'followMarket' => true,
            'manualBdtPerUsd' => $manual,
        ];
    }

    /** @param array{followMarket?:bool,manualBdtPerUsd?:float} $raw */
    public static function saveAdmin(array $raw): array
    {
        $prev = self::load();
        $follow = (bool) ($raw['followMarket'] ?? true);
        $manual = max(1.0, min(500.0, (float) ($raw['manualBdtPerUsd'] ?? ($prev['manualBdtPerUsd'] ?? self::FALLBACK))));
        self::persist([
            'followMarket' => $follow,
            'manualBdtPerUsd' => $manual,
            'bdtPerUsd' => $follow ? (float) ($prev['bdtPerUsd'] ?? $manual) : $manual,
            'source' => $follow ? (string) ($prev['source'] ?? 'market') : 'manual',
            'updatedAt' => (string) ($prev['updatedAt'] ?? gmdate('c')),
        ]);
        return self::snapshot($follow);
    }

    /** @return array<string,mixed> */
    private static function load(): array
    {
        $row = Db::one('SELECT v FROM settings WHERE k = ?', [self::SETTINGS_KEY]);
        if ($row === null) {
            return [
                'followMarket' => true,
                'manualBdtPerUsd' => self::FALLBACK,
                'bdtPerUsd' => self::FALLBACK,
                'source' => 'fallback',
                'updatedAt' => '',
            ];
        }
        $j = json_decode((string) $row['v'], true);
        return is_array($j) ? $j : [];
    }

    /** @param array<string,mixed> $data */
    private static function persist(array $data): void
    {
        Db::run(
            'INSERT INTO settings (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)',
            [self::SETTINGS_KEY, json_encode($data)]
        );
    }

    /** @return array{bdtPerUsd:float,source:string}|null */
    private static function fetchMarket(): ?array
    {
        $urls = [
            'https://open.er-api.com/v6/latest/USD',
            'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json',
        ];
        foreach ($urls as $url) {
            try {
                $raw = self::httpGet($url);
                if ($raw === null || $raw === '') {
                    continue;
                }
                $j = json_decode($raw, true);
                if (!is_array($j)) {
                    continue;
                }
                $bdt = null;
                if (isset($j['rates']['BDT'])) {
                    $bdt = (float) $j['rates']['BDT'];
                } elseif (isset($j['usd']['bdt'])) {
                    $bdt = (float) $j['usd']['bdt'];
                }
                if ($bdt !== null && $bdt >= 50.0 && $bdt <= 500.0) {
                    return ['bdtPerUsd' => round($bdt, 4), 'source' => 'market'];
                }
            } catch (\Throwable $e) {
                error_log('[UsdMarketRate] ' . $e->getMessage());
            }
        }
        return null;
    }

    private static function httpGet(string $url): ?string
    {
        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            if ($ch === false) {
                return null;
            }
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_CONNECTTIMEOUT => 6,
                CURLOPT_TIMEOUT => 10,
                CURLOPT_HTTPHEADER => ['Accept: application/json', 'User-Agent: PikoPe/1.0'],
            ]);
            $body = curl_exec($ch);
            $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            if ($body === false || $code >= 400) {
                return null;
            }
            return (string) $body;
        }
        $ctx = stream_context_create([
            'http' => ['timeout' => 10, 'header' => "Accept: application/json\r\nUser-Agent: PikoPe/1.0\r\n"],
            'ssl' => ['verify_peer' => true, 'verify_peer_name' => true],
        ]);
        $body = @file_get_contents($url, false, $ctx);
        return $body === false ? null : $body;
    }
}
