<?php
declare(strict_types=1);

namespace App;

/**
 * Master admin at /admin, behind HTTP Basic auth. Disabled (404) until
 * ADMIN_USER and ADMIN_PASS are set in .env.
 *
 * Covers the same games as the app (pool, ludo, carrom): player edit, coin
 * and gem changes through the wallet ledger, full wallet and match history,
 * live matches, economy and notices.
 */
final class Admin
{
    private const PER = 40;

    public static function handle(string $method, string $path): never
    {
        if (!AdminAuth::isEnabled()) {
            throw ApiError::notFound('No such endpoint');
        }
        self::assertAdminIpAllowed();
        RateLimit::hit('admin:' . RateLimit::ip(), 120, 300);
        [$givenUser, $givenPass] = Http::basicAuth();
        if (!AdminAuth::verify($givenUser, $givenPass)) {
            RateLimit::hit('admin-fail:' . RateLimit::ip(), 15, 900);
            header('WWW-Authenticate: Basic realm="PikoPe master admin"');
            http_response_code(401);
            exit('Sign in required');
        }
        $csrf = AdminAuth::csrfToken();

        if ($method === 'POST') {
            self::requireCsrf($csrf);
            switch ($path) {
                case '/admin/ban':
                    self::ban();
                case '/admin/economy':
                    self::saveEconomy();
                case '/admin/referral':
                    self::saveReferral();
                case '/admin/adjust':
                    self::adjust();
                case '/admin/player/save':
                    self::savePlayer();
                case '/admin/player/signout':
                    self::signOut();
                case '/admin/notice':
                    self::createNotice();
                case '/admin/notice/off':
                    Db::run('UPDATE notices SET active = 0 WHERE id = ?', [(int) ($_POST['id'] ?? 0)]);
                    self::back('/admin/notices', 'Notice deactivated.');
                case '/admin/coin-shop/global':
                    self::saveCoinShopGlobal();
                case '/admin/coin-shop/pack':
                    self::saveCoinShopPack();
                case '/admin/coin-shop/delete':
                    self::deleteCoinShopPack();
                case '/admin/otp-sms':
                    self::saveOtpSms();
                case '/admin/redeem/save':
                    self::saveRedeemConfig();
                case '/admin/redeem/approve':
                    self::reviewRedeem(true);
                case '/admin/redeem/reject':
                    self::reviewRedeem(false);
                case '/admin/deposit/save':
                    self::saveDepositConfig();
                case '/admin/zinipay/save':
                    self::saveZiniPayConfig();
                case '/admin/deposit/approve':
                    self::reviewDeposit(true);
                case '/admin/deposit/reject':
                    self::reviewDeposit(false);
                case '/admin/promotions':
                    self::savePromotions();
                case '/admin/push/save':
                    self::savePushConfig();
                case '/admin/push/broadcast':
                    self::pushBroadcast();
                case '/admin/push/test':
                    self::pushTest();
                case '/admin/support':
                    self::saveSupport();
                case '/admin/app-update':
                    self::saveAppUpdate();
                case '/admin/account':
                    self::saveAdminAccount();
                case '/admin/alerts/read':
                    AdminAlert::markAllRead();
                    self::back('/admin/alerts', 'All alerts marked read.');
                case '/admin/transfer/save':
                    self::saveTransferConfig();
            }
            throw ApiError::notFound('No such endpoint');
        }

        if ($method !== 'GET') {
            throw ApiError::notFound('No such endpoint');
        }
        match ($path) {
            '/admin' => self::dashboard(),
            '/admin/players' => self::playersPage(),
            '/admin/player' => self::playerPage($csrf, (int) ($_GET['id'] ?? 0)),
            '/admin/matches' => self::matchesPage(),
            '/admin/match' => self::matchPage((int) ($_GET['id'] ?? 0)),
            '/admin/wallet' => self::walletPage(),
            '/admin/referrals' => self::referralsPage($csrf),
            '/admin/economy' => self::economyPage($csrf),
            '/admin/coin-shop' => self::coinShopPage($csrf),
            '/admin/otp-sms' => self::otpSmsPage($csrf),
            '/admin/redeems' => self::redeemsPage($csrf),
            '/admin/deposits' => self::depositsPage($csrf),
            '/admin/notices' => self::noticesPage($csrf),
            '/admin/promotions' => self::promotionsPage($csrf),
            '/admin/push' => self::pushPage($csrf),
            '/admin/support' => self::supportPage($csrf),
            '/admin/app-update' => self::appUpdatePage($csrf),
            '/admin/account' => self::accountPage($csrf),
            '/admin/alerts' => self::alertsPage($csrf),
            '/admin/transfer' => self::transferPage($csrf),
            '/admin/zinipay' => self::ziniPayPage($csrf),
            default => throw ApiError::notFound('No such endpoint'),
        };
    }

    private static function requireCsrf(string $csrf): void
    {
        if (!hash_equals($csrf, (string) ($_POST['csrf'] ?? ''))) {
            http_response_code(400);
            exit('Expired form, reload the page');
        }
    }

    private static function back(string $to = '/admin', ?string $ok = null, ?string $err = null): never
    {
        if ($ok !== null || $err !== null) {
            $sep = str_contains($to, '?') ? '&' : '?';
            if ($err !== null) {
                $to .= $sep . 'flash=err&msg=' . rawurlencode($err);
            } else {
                $to .= $sep . 'flash=ok&msg=' . rawurlencode($ok ?? 'Saved successfully.');
            }
        }
        header('Location: ' . self::base() . $to);
        exit;
    }

    private static function renderFlash(): void
    {
        $kind = (string) ($_GET['flash'] ?? '');
        $msg = trim((string) ($_GET['msg'] ?? ''));
        if ($msg === '' || !in_array($kind, ['ok', 'err'], true)) {
            return;
        }
        if (mb_strlen($msg) > 500) {
            $msg = mb_substr($msg, 0, 500) . '…';
        }
        $class = $kind === 'ok' ? 'ok' : 'bad';
        echo '<div class="alert ', $class, '" role="status">', self::e($msg), '</div>',
            '<script>(function(){try{var u=new URL(location.href);if(!u.searchParams.has("flash"))return;',
            'u.searchParams.delete("flash");u.searchParams.delete("msg");',
            'history.replaceState({}, "", u.pathname+(u.search?u.search:"")+u.hash);}catch(e){}})();</script>';
    }

    /** Only in-app admin paths, so a form cannot redirect the browser elsewhere. */
    private static function next(string $fallback): string
    {
        $n = (string) ($_POST['next'] ?? '');
        if ($n === '' || !str_starts_with($n, '/admin') || str_contains($n, '//') || str_contains($n, "\n") || str_contains($n, '\\')) {
            return $fallback;
        }
        return $n;
    }

    private static function ban(): never
    {
        $id = (int) ($_POST['id'] ?? 0);
        $banned = ($_POST['banned'] ?? '0') === '1' ? 1 : 0;
        Db::run('UPDATE users SET banned = ? WHERE id = ? AND is_bot = 0', [$banned, $id]);
        if ($banned) {
            Db::run('DELETE FROM auth_tokens WHERE user_id = ?', [$id]);
        }
        self::back(self::next('/admin/player?id=' . $id), 'Player ban status updated.');
    }

    private static function saveEconomy(): never
    {
        try {
            Economy::save(self::economyFromPost());
        } catch (ApiError $e) {
            self::fail($e->getMessage(), '/admin/economy');
        }
        self::back('/admin/economy', 'Economy settings saved.');
    }

    /** @return array<string,mixed> */
    private static function economyFromPost(): array
    {
        $c = Economy::config();
        $c['rakePercent'] = (int) ($_POST['rakePercent'] ?? $c['rakePercent']);
        $c['winPayoutPercent'] = (int) ($_POST['winPayoutPercent'] ?? $c['winPayoutPercent'] ?? 200);
        $c['startCoins'] = (int) ($_POST['startCoins'] ?? $c['startCoins']);
        $c['referralPercent'] = (int) ($c['referralPercent'] ?? 0);
        $c['billiardStakes'] = self::fixedIntListFromPost('billiardStakes', 8);
        $c['pokerStakes'] = self::fixedIntListFromPost('pokerStakes', 8);
        $c['stakeNames'] = self::fixedStringListFromPost('stakeNames', 8);
        $c['dailyBonus'] = self::intListFromPost('dailyBonus');
        $c['dailyGems'] = self::intListFromPost('dailyGems', allowZero: true);
        $xs = $_POST['jackpot_x'] ?? [];
        $ws = $_POST['jackpot_weight'] ?? [];
        if (!is_array($xs) || !is_array($ws)) {
            throw ApiError::badRequest('Jackpot rows are invalid');
        }
        $jackpot = [];
        $n = min(count($xs), count($ws));
        for ($i = 0; $i < $n; $i++) {
            $x = (int) $xs[$i];
            $w = (int) $ws[$i];
            if ($x < 1 && $w < 1) {
                continue;
            }
            $jackpot[] = ['x' => $x, 'weight' => $w];
        }
        if ($jackpot === []) {
            throw ApiError::badRequest('Add at least one jackpot row');
        }
        $c['jackpot'] = $jackpot;
        return $c;
    }

    /** @return list<int> */
    private static function intListFromPost(string $key, bool $allowZero = false): array
    {
        $raw = $_POST[$key] ?? [];
        if (!is_array($raw)) {
            throw ApiError::badRequest("$key must be a list of numbers");
        }
        $out = [];
        foreach ($raw as $v) {
            $n = (int) $v;
            if ($allowZero ? $n < 0 : $n <= 0) {
                continue;
            }
            $out[] = $n;
        }
        if ($out === []) {
            throw ApiError::badRequest("$key needs at least one valid number");
        }
        return $out;
    }

    /** @return list<int> */
    private static function fixedIntListFromPost(string $key, int $count): array
    {
        $out = self::intListFromPost($key);
        if (count($out) !== $count) {
            throw ApiError::badRequest("$key must have exactly $count values");
        }
        return $out;
    }

    /** @return list<string> */
    private static function fixedStringListFromPost(string $key, int $count): array
    {
        $raw = $_POST[$key] ?? [];
        if (!is_array($raw)) {
            throw ApiError::badRequest("$key must be a list of labels");
        }
        $out = [];
        foreach ($raw as $v) {
            $s = strtoupper(preg_replace('/[^A-Za-z0-9 _-]/', '', trim((string) $v)) ?? '');
            $out[] = substr($s === '' ? 'LEVEL' : $s, 0, 16);
        }
        if (count($out) !== $count) {
            throw ApiError::badRequest("$key must have exactly $count labels");
        }
        return $out;
    }

    private static function saveReferral(): never
    {
        $c = Economy::config();
        $c['referralPercent'] = (int) ($_POST['percent'] ?? 0);
        try {
            Economy::save($c);
        } catch (ApiError $e) {
            self::fail($e->getMessage(), '/admin/referrals');
        }
        self::back('/admin/referrals', 'Referral settings saved.');
    }

    /** Optional comma-separated IPs in ADMIN_IP_ALLOWLIST (.env). */
    private static function assertAdminIpAllowed(): void
    {
        $list = Config::get('ADMIN_IP_ALLOWLIST');
        if ($list === '') {
            return;
        }
        $ip = RateLimit::ip();
        foreach (array_filter(array_map('trim', explode(',', $list))) as $allowed) {
            if ($allowed === $ip) {
                return;
            }
        }
        throw ApiError::notFound('No such endpoint');
    }

    /** Grants, deducts, or sets coins/gems. Every change is a wallet_tx row. */
    private static function adjust(): never
    {
        $id = (int) ($_POST['id'] ?? 0);
        $raw = (int) ($_POST['amount'] ?? 0);
        $currency = ($_POST['currency'] ?? 'coins') === 'gems' ? 'gems' : 'coins';
        $mode = (string) ($_POST['mode'] ?? 'delta');
        $reason = trim((string) ($_POST['reason'] ?? ''));
        $back = '/admin/player?id=' . $id;
        if ($id <= 0) {
            self::fail('Give a player id.', '/admin/players');
        }
        if (!in_array($mode, ['add', 'subtract', 'set', 'delta'], true)) {
            self::fail('Unknown balance action.', $back);
        }
        try {
            Db::transaction(static function () use ($id, $raw, $currency, $mode, $reason): void {
                $column = $currency === 'gems' ? 'gems' : 'coins';
                $row = Db::one("SELECT $column AS balance FROM users WHERE id = ? AND is_bot = 0 FOR UPDATE", [$id]);
                if ($row === null) {
                    throw ApiError::notFound('No such player.');
                }
                $amount = match ($mode) {
                    'add' => abs($raw),
                    'subtract' => -abs($raw),
                    'set' => $raw - (int) $row['balance'],
                    default => $raw,
                };
                if ($amount === 0) {
                    throw ApiError::badRequest('That does not change the balance.');
                }
                $note = $reason === '' ? $mode : $reason;
                Economy::move($id, $amount, 'admin:' . substr($note, 0, 30), null, $currency);
            });
        } catch (ApiError $e) {
            self::fail($e->getMessage(), $back);
        }
        self::back($back, 'Wallet balance updated.');
    }

    private static function savePlayer(): never
    {
        $id = (int) ($_POST['id'] ?? 0);
        $u = Db::one('SELECT * FROM users WHERE id = ? AND is_bot = 0', [$id]);
        $back = '/admin/player?id=' . $id;
        if ($u === null) {
            self::fail('No such player.', '/admin/players');
        }
        $name = trim((string) ($_POST['display_name'] ?? ''));
        if (preg_match('/^[\p{L}\p{N} _.\-]{1,24}$/u', $name) !== 1) {
            self::fail('Name must be 1-24 letters, numbers, spaces, _ . or -.', $back);
        }
        $phoneRaw = trim((string) ($_POST['phone'] ?? ''));
        $phone = null;
        if ($phoneRaw !== '') {
            try {
                $phone = Phone::normalize($phoneRaw);
            } catch (ApiError $e) {
                self::fail($e->getMessage(), $back);
            }
        }
        if ($phone !== null && Db::one('SELECT id FROM users WHERE phone = ? AND id <> ?', [$phone, $id]) !== null) {
            self::fail('Another player already uses that mobile number.', $back);
        }
        $cue = (string) ($_POST['cue'] ?? 'classic');
        if (!isset(Economy::CUES[$cue])) {
            $cue = 'classic';
        }
        $skin = trim((string) ($_POST['table_skin'] ?? ''));
        if (preg_match('/^[a-z0-9_]{1,32}$/', $skin) !== 1) {
            self::fail('Table skin must be 1-32 letters, numbers or _.', $back);
        }
        $avatar = (string) ($_POST['avatar'] ?? '');
        if (preg_match('/^asset:avatar_[1-6]$/', $avatar) !== 1) {
            $avatar = (string) $u['avatar'];
        }
        $xp = max(0, (int) ($_POST['xp'] ?? 0));
        $wins = max(0, (int) ($_POST['wins'] ?? 0));
        $games = max(0, (int) ($_POST['games'] ?? 0));
        $nameSet = ($_POST['name_set'] ?? '') === '1' ? 1 : 0;
        $password = (string) ($_POST['new_password'] ?? '');
        if ($password !== '' && strlen($password) < 8) {
            self::fail('A new password must be at least 8 characters.', $back);
        }
        if ($password !== '' && $phone === null) {
            self::fail('Set a mobile number before giving this player a password.', $back);
        }
        Db::transaction(static function () use ($id, $name, $phone, $avatar, $skin, $xp, $wins, $games, $cue, $nameSet, $password): void {
            Db::run(
                'UPDATE users SET display_name = ?, phone = ?, avatar = ?, table_skin = ?, xp = ?, wins = ?, games = ?, cue = ?, name_set = ?, is_guest = ? WHERE id = ?',
                [$name, $phone, $avatar, $skin, $xp, $wins, $games, $cue, $nameSet, $phone === null ? 1 : 0, $id]
            );
            Db::run('INSERT IGNORE INTO user_items (user_id, kind, item) VALUES (?, \'cue\', ?)', [$id, $cue]);
            if ($password !== '') {
                Db::run('UPDATE users SET password_hash = ? WHERE id = ?', [password_hash($password, PASSWORD_DEFAULT), $id]);
            }
        });
        self::back($back, 'Player profile saved.');
    }

    private static function signOut(): never
    {
        $id = (int) ($_POST['id'] ?? 0);
        Db::run('DELETE FROM auth_tokens WHERE user_id = ?', [$id]);
        self::back('/admin/player?id=' . $id, 'Player signed out on all devices.');
    }

    private static function createNotice(): never
    {
        $title = trim((string) ($_POST['title'] ?? ''));
        $body = trim((string) ($_POST['body'] ?? ''));
        $kind = ($_POST['kind'] ?? 'news') === 'banner' ? 'banner' : 'news';
        $expires = trim((string) ($_POST['expires'] ?? ''));
        if ($title === '' || $body === '' || mb_strlen($title) > 80 || mb_strlen($body) > 500) {
            self::fail('A title (max 80) and body (max 500) are required.', '/admin/notices');
        }
        $expiresAt = null;
        if ($expires !== '') {
            $ts = strtotime($expires);
            $expiresAt = $ts === false ? null : date('Y-m-d H:i:s', $ts);
        }
        Db::run('INSERT INTO notices (title, body, kind, expires_at) VALUES (?, ?, ?, ?)', [$title, $body, $kind, $expiresAt]);
        if (($_POST['push'] ?? '0') === '1') {
            Push::broadcast($title, $body);
        }
        self::back('/admin/notices', 'Notice published.');
    }

    private static function base(): string
    {
        return rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
    }

    private static function e(mixed $v): string
    {
        return htmlspecialchars((string) $v, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }

    /** MySQL returns tinyint as the string "0" or "1"; only "1" is on. */
    private static function on(mixed $v): bool
    {
        return (int) $v === 1;
    }

    private static function csrfField(string $csrf): string
    {
        return '<input type="hidden" name="csrf" value="' . self::e($csrf) . '">';
    }

    private static function pageOf(string $key): int
    {
        $p = (int) ($_GET[$key] ?? 1);
        return max(1, $p);
    }

    private static function n(string $sql, array $params = []): int
    {
        return (int) Db::one($sql, $params)['n'];
    }

    /** @param array<string,mixed> $keep */
    private static function pager(string $param, int $page, int $total, array $keep = []): string
    {
        $pages = (int) ceil($total / self::PER);
        if ($pages <= 1) {
            return '';
        }
        $html = '<nav class="pager">';
        $start = max(1, $page - 3);
        $end = min($pages, $page + 3);
        for ($i = $start; $i <= $end; $i++) {
            $q = $keep;
            $q[$param] = $i;
            $html .= '<a class="' . ($i === $page ? 'on' : '') . '" href="' . self::e(self::base() . Http::path() . '?' . http_build_query($q)) . '">' . $i . '</a>';
        }
        if ($end < $pages) {
            $q = $keep;
            $q[$param] = $pages;
            $html .= '<a href="' . self::e(self::base() . Http::path() . '?' . http_build_query($q)) . '">' . $pages . '</a>';
        }
        return $html . '</nav>';
    }

    private static function head(string $title): void
    {
        header('Content-Type: text/html; charset=utf-8');
        header('Cache-Control: no-store, no-cache, must-revalidate');
        header('X-Frame-Options: DENY');
        header('X-Content-Type-Options: nosniff');
        header('Referrer-Policy: same-origin');
        header('Permissions-Policy: geolocation=(), microphone=(), camera=()');
        header("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");
        echo '<!doctype html><html lang="en"><head><meta charset="utf-8">',
            '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">',
            '<meta name="robots" content="noindex,nofollow">',
            '<meta name="theme-color" content="#ffffff">',
            '<title>', self::e($title), ' · PikoPe Admin</title><style>',
            self::adminCss(),
            '</style></head><body>';
    }

    private static function adminCss(): string
    {
        return <<<'CSS'
:root{
  --bg:#fff;--surface:#fff;--surface2:#fafafa;--surface3:#f5f5f5;
  --line:#ececec;--line2:#d4d4d4;--text:#171717;--muted:#737373;
  --brand:#2563eb;--brand-hover:#1d4ed8;--brand-soft:#eff6ff;
  --accent:#0ea5e9;--ok:#16a34a;--ok-bg:#f0fdf4;--bad:#dc2626;--bad-bg:#fef2f2;
  --warn:#ea580c;--warn-bg:#fff7ed;
  --shadow:0 1px 3px rgba(0,0,0,.04);--shadow-md:0 4px 14px rgba(0,0,0,.06);
  --radius:16px;--radius-sm:12px;--sidebar-w:280px;
}
*{box-sizing:border-box}
html{background:#fff}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-font-smoothing:antialiased}
a{color:var(--brand);text-decoration:none;transition:color .12s,background .12s}a:hover{color:var(--brand-hover)}
.shell{display:flex;min-height:100vh;width:100%;background:#fff}
.nav-wrap{flex:none;width:var(--sidebar-w);background:#fff;border-right:1px solid var(--line);position:sticky;top:0;align-self:flex-start;max-height:100vh;overflow-y:auto}
.nav-wrap summary{list-style:none;cursor:pointer;padding:16px 20px;font-weight:700;font-size:15px;color:var(--text);background:#fff;border-bottom:1px solid var(--line);display:none}
.nav-wrap summary::-webkit-details-marker{display:none}
aside.sidebar{padding:24px 16px 32px}
.brand-block{padding:4px 12px 20px;margin-bottom:8px;border-bottom:1px solid var(--line)}
.brand-row{display:flex;align-items:center;gap:14px}
.brand-logo{width:52px;height:52px;border-radius:14px;object-fit:cover;border:1px solid var(--line);box-shadow:var(--shadow);background:#fff}
.brand{font-size:24px;font-weight:800;letter-spacing:-.03em;color:var(--text);line-height:1.1}
.brand span{color:var(--brand)}
.role{font-size:13px;color:var(--muted);margin:8px 0 0;font-weight:500}
nav a .nav-sub{display:block;font-size:11px;font-weight:500;color:#a3a3a3;margin-top:2px}
nav a.on .nav-sub{color:#60a5fa}
.nav-group{margin:20px 0 6px;font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:#a3a3a3;padding:0 12px}
nav{display:flex;flex-direction:column;gap:2px}
nav a{display:flex;align-items:center;gap:10px;padding:12px 14px;border-radius:var(--radius-sm);color:#404040;font-weight:600;font-size:14px;border:1px solid transparent;min-height:48px}
nav a>span:nth-child(2){flex:1;min-width:0}
nav a:hover{background:var(--surface3);text-decoration:none;color:var(--text)}
nav a.on{background:var(--brand-soft);color:var(--brand);border-color:#bfdbfe;box-shadow:inset 3px 0 0 var(--brand)}
.nav-dot{width:8px;height:8px;border-radius:50%;background:#d4d4d4;flex:none}
nav a.on .nav-dot{background:var(--brand)}
.nav-badge{margin-left:auto;min-width:24px;text-align:center;background:var(--warn);color:#fff;font-size:11px;font-weight:800;padding:4px 8px;border-radius:999px;line-height:1}
nav a.on .nav-badge{background:var(--brand)}
.side-note{margin-top:24px;padding:14px;border-radius:var(--radius-sm);background:var(--surface2);border:1px solid var(--line);font-size:12px;line-height:1.5;color:var(--muted)}
main{flex:1;min-width:0;padding:28px 28px 48px;max-width:none;background:#fff}
.page-head{margin:0 0 28px;padding:0 0 20px;border-bottom:1px solid var(--line)}
h1{font-size:30px;margin:0;font-weight:800;letter-spacing:-.03em;color:var(--text)}
.page-lead{color:var(--muted);font-size:16px;margin:10px 0 0;max-width:720px;line-height:1.55;font-weight:400}
h2{font-size:12px;margin:0 0 14px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:#a3a3a3}
.section{margin:0 0 32px}
.stats{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:14px;margin:0 0 8px}
.stat{background:#fff;border:1px solid var(--line);border-radius:var(--radius);padding:18px 20px;box-shadow:var(--shadow);transition:border-color .15s,box-shadow .15s}
.stat:hover{border-color:#d4d4d4;box-shadow:var(--shadow-md)}
.stat b{display:block;font-size:28px;font-weight:800;line-height:1.05;color:var(--text);letter-spacing:-.02em}
.stat span{color:var(--muted);font-size:13px;margin-top:8px;display:block;font-weight:500}
.stat.accent b{color:var(--brand)}
.quick-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:12px;margin:0 0 8px}
.quick-card{display:flex;flex-direction:column;gap:6px;padding:18px 20px;background:#fff;border:1px solid var(--line);border-radius:var(--radius);color:var(--text);font-weight:600;font-size:15px;min-height:88px;box-shadow:var(--shadow);transition:all .15s;text-decoration:none!important}
.quick-card:hover{border-color:var(--brand);box-shadow:var(--shadow-md);color:var(--brand);transform:translateY(-1px)}
.quick-card small{font-size:12px;font-weight:500;color:var(--muted)}
.quick-card.has-pending{border-color:#fed7aa;background:var(--warn-bg)}
.quick-card.has-pending small{color:var(--warn);font-weight:700}
.card{background:#fff;border:1px solid var(--line);border-radius:var(--radius);padding:22px 24px;margin:0 0 16px;box-shadow:var(--shadow)}
.card h2{margin:-2px 0 16px;color:var(--text);font-size:18px;letter-spacing:-.02em;text-transform:none;font-weight:700}
.card-title{font-size:18px;font-weight:700;margin:0 0 16px;letter-spacing:-.02em}
.alert{border-radius:var(--radius-sm);padding:16px 18px;margin:0 0 18px;border:1px solid;font-size:14px;line-height:1.5}
.alert.bad{background:var(--bad-bg);border-color:#fecaca;color:var(--bad)}
.alert.ok{background:var(--ok-bg);border-color:#bbf7d0;color:var(--ok)}
.alert.ok::before{content:"Success: ";font-weight:700}
.alert.bad::before{content:"Error: ";font-weight:700}
.search-card{background:#fff;border:1px solid var(--line);border-radius:var(--radius);padding:20px 22px;margin:0 0 20px;box-shadow:var(--shadow)}
.breadcrumb{margin:-8px 0 24px}
label.check{flex-direction:row;align-items:center;gap:12px;font-size:15px;font-weight:500;color:var(--text);padding:8px 0}
label.check input{width:20px;height:20px;min-height:20px;padding:0;flex:none;accent-color:var(--brand)}
.grid .span2{grid-column:1/-1}
@media(min-width:640px){.grid .span2{grid-column:span 2}}
.table-scroll{width:100%;overflow-x:auto;-webkit-overflow-scrolling:touch;border:1px solid var(--line);border-radius:var(--radius);background:#fff;margin:10px 0 18px;box-shadow:var(--shadow)}
.table-scroll table{margin:0;border:0;border-radius:0;min-width:640px}
table.one{width:max-content;min-width:100%}
table.one td,table.one th{white-space:nowrap}
table{border-collapse:collapse;width:100%;background:#fff}
td,th{padding:13px 16px;border-bottom:1px solid var(--line);text-align:left;vertical-align:middle}
th{background:#fafafa;color:var(--muted);font-size:11px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;white-space:nowrap;position:sticky;top:0}
tbody tr:hover td{background:#fafafa}
tr:last-child td{border-bottom:0}
p,.hint{color:#525252;max-width:780px;line-height:1.65;margin:0 0 14px;font-size:14px}
.good{color:var(--ok);font-weight:600}.bad{color:var(--bad);font-weight:600}.muted{color:var(--muted)}
input,select,textarea{background:#fff;color:var(--text);border:1px solid var(--line2);border-radius:var(--radius-sm);padding:12px 14px;font:inherit;width:100%;transition:border-color .15s,box-shadow .15s;font-size:15px}
input:focus,select:focus,textarea:focus{outline:none;border-color:var(--brand);box-shadow:0 0 0 3px var(--brand-soft)}
textarea{font-family:ui-monospace,monospace;font-size:13px;min-height:120px}
label{display:flex;flex-direction:column;gap:8px;font-size:13px;font-weight:600;color:#525252}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px 20px}
button,.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;cursor:pointer;background:var(--brand);color:#fff;border:0;border-radius:var(--radius-sm);padding:12px 22px;font-weight:700;font-size:15px;min-height:48px;transition:background .15s,transform .05s,box-shadow .15s;text-decoration:none;box-shadow:var(--shadow)}
button:hover,.btn:hover{background:var(--brand-hover);text-decoration:none;color:#fff;box-shadow:var(--shadow-md)}
button:active,.btn:active{transform:translateY(1px)}
button.ghost,.btn.ghost{background:#fff;color:var(--text);border:1px solid var(--line2);box-shadow:none}
button.ghost:hover,.btn.ghost:hover{background:var(--surface2);box-shadow:var(--shadow)}
button.danger,.btn.danger{background:var(--bad)}button.danger:hover{background:#b91c1c}
button.ok,.btn.ok{background:var(--ok)}button.ok:hover{background:#15803d}
form.inline{display:inline-flex;gap:8px;flex-wrap:nowrap;align-items:center;margin:0}
form.inline input{width:150px;min-width:120px;max-width:180px;padding:8px 10px;min-height:40px}
form.inline button{min-height:40px;padding:8px 14px;white-space:nowrap}
td.actions{white-space:nowrap}
td.actions form{margin-right:6px}
.row{display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end}
.row label{flex:1 1 180px;min-width:150px}
.pager{display:flex;gap:8px;margin:18px 0;flex-wrap:wrap}
.pager a{background:#fff;border:1px solid var(--line);border-radius:var(--radius-sm);padding:10px 16px;color:#404040;min-width:44px;text-align:center;font-weight:600;box-shadow:var(--shadow)}
.pager a.on{background:var(--brand);color:#fff;border-color:var(--brand);text-decoration:none}
.filters{display:flex;gap:10px;flex-wrap:wrap;margin:0 0 18px}
.filters a{background:#fff;border:1px solid var(--line);border-radius:999px;padding:10px 18px;color:#404040;font-size:14px;font-weight:600;box-shadow:var(--shadow)}
.filters a.on{background:var(--brand-soft);color:var(--brand);border-color:#93c5fd;text-decoration:none}
.pill{display:inline-block;border-radius:999px;padding:5px 12px;font-size:11px;font-weight:700;background:#f5f5f5;color:#525252}
.pill.bad{background:var(--bad-bg);color:var(--bad)}.pill.good{background:var(--ok-bg);color:var(--ok)}
code{font-family:ui-monospace,monospace;font-size:12px;background:#f5f5f5;padding:4px 8px;border-radius:8px;border:1px solid var(--line)}
.link-row{margin:14px 0;display:flex;flex-wrap:wrap;gap:10px}.link-row a.btn.ghost{padding:10px 16px;min-height:auto;font-size:14px}
@media(max-width:960px){
  .shell{flex-direction:column}
  .nav-wrap{width:100%;border-right:0;border-bottom:1px solid var(--line);position:relative;max-height:none}
  .nav-wrap summary{display:block}
  aside.sidebar{padding:12px 14px 20px}
  .nav-group{width:100%;padding:8px 10px 4px}
  nav{flex-direction:row;flex-wrap:wrap;gap:8px}
  nav a{padding:12px 14px;font-size:13px;flex:1 1 auto;min-width:calc(50% - 10px);justify-content:flex-start}
  main{padding:20px 16px 40px;max-width:none}
  h1{font-size:24px}
  .grid{grid-template-columns:1fr}
  .row{align-items:stretch}
  .row button,.row .btn,.row label{width:100%}
  form.inline{width:100%;flex-direction:column;align-items:stretch}
  form.inline input{max-width:none;width:100%}
  td.actions form.inline{width:auto;flex-direction:row}
  td.actions form.inline input{width:140px;max-width:160px}
  .stats,.quick-grid{grid-template-columns:repeat(2,minmax(0,1fr))}
}
@media(min-width:961px){.nav-wrap[open] summary,.nav-wrap summary{display:none}}
CSS;
    }

    private static function tableScrollOpen(): string
    {
        return '<div class="table-scroll">';
    }

    private static function tableScrollClose(): string
    {
        return '</div>';
    }

    private static function pendingNavCounts(): array
    {
        static $cache = null;
        if ($cache === null) {
            $cache = [
                'deposits' => self::n("SELECT COUNT(*) AS n FROM coin_deposit_requests WHERE status = 'pending'"),
                'redeems' => self::n("SELECT COUNT(*) AS n FROM redeem_requests WHERE status = 'pending'"),
                'alerts' => AdminAlert::unreadCount(),
            ];
        }

        return $cache;
    }

    private static function begin(string $title, string $active): void
    {
        self::head($title);
        $base = self::base();
        $pending = self::pendingNavCounts();
        $logo = self::brandLogoUrl();
        $groups = [
            'Overview' => [
                'dashboard' => ['Dashboard', '/admin'],
                'players' => ['Players', '/admin/players'],
                'matches' => ['Matches', '/admin/matches'],
                'wallet' => ['Wallet', '/admin/wallet'],
            ],
            'Money' => [
                'deposits' => ['Coin add', '/admin/deposits'],
                'zinipay' => ['ZiniPay (auto)', '/admin/zinipay'],
                'redeems' => ['Redeem', '/admin/redeems'],
                'transfer' => ['Coin transfer', '/admin/transfer'],
                'coin-shop' => ['Coin shop', '/admin/coin-shop'],
                'referrals' => ['Referrals', '/admin/referrals'],
            ],
            'Security' => [
                'alerts' => ['Signals / alerts', '/admin/alerts'],
            ],
            'Settings' => [
                'economy' => ['Economy', '/admin/economy'],
                'promotions' => ['Promotions', '/admin/promotions'],
                'push' => ['Push (APK)', '/admin/push'],
                'otp-sms' => ['SMS OTP', '/admin/otp-sms'],
                'notices' => ['Notices', '/admin/notices'],
                'support' => ['Support links', '/admin/support'],
                'app-update' => ['App update', '/admin/app-update'],
                'account' => ['Admin password', '/admin/account'],
            ],
        ];
        echo '<div class="shell"><details class="nav-wrap" open><summary>Menu — PikoPe Admin</summary>',
            '<aside class="sidebar"><div class="brand-block"><div class="brand-row">';
        if ($logo !== '') {
            echo '<img class="brand-logo" src="', self::e($logo), '" alt="PikoPe" width="52" height="52">';
        }
        echo '<div><div class="brand">Piko<span>Pe</span></div>',
            '<div class="role">Admin panel — easy control</div></div></div></div>';
        foreach ($groups as $group => $items) {
            echo '<div class="nav-group">', self::e($group), '</div><nav>';
            foreach ($items as $key => [$label, $href]) {
                $badge = '';
                if ($key === 'deposits' && $pending['deposits'] > 0) {
                    $badge = '<span class="nav-badge">' . self::e($pending['deposits']) . '</span>';
                } elseif ($key === 'redeems' && $pending['redeems'] > 0) {
                    $badge = '<span class="nav-badge">' . self::e($pending['redeems']) . '</span>';
                } elseif ($key === 'alerts' && $pending['alerts'] > 0) {
                    $badge = '<span class="nav-badge">' . self::e($pending['alerts']) . '</span>';
                }
                echo '<a class="', $key === $active ? 'on' : '', '" href="', self::e($base . $href), '">',
                    '<span class="nav-dot"></span><span>', self::e($label), '</span>', $badge, '</a>';
            }
            echo '</nav>';
        }
        echo '<p class="side-note"><strong>Security:</strong> HTTPS, strong password (<a href="', self::e($base), '/admin/account">change here</a>), optional ADMIN_IP_ALLOWLIST in .env.</p>',
            '</aside></details><main><header class="page-head"><h1>', self::e($title), '</h1>';
        self::renderFlash();
    }

    /** Big tap-friendly shortcuts (dashboard). */
    private static function quickLinks(): void
    {
        $base = self::base();
        $pending = self::pendingNavCounts();
        $items = [
            ['Coin add (review)', '/admin/deposits?status=pending', 'Approve bKash / Nagad', $pending['deposits']],
            ['Redeem (review)', '/admin/redeems?status=pending', 'Cash out requests', $pending['redeems']],
            ['Security signals', '/admin/alerts', 'Redeem abuse, hacks, transfers', $pending['alerts']],
            ['Coin transfer fee', '/admin/transfer', 'Fee % and limits', 0],
            ['ZiniPay auto add', '/admin/zinipay', 'API key & WebView pay', 0],
            ['Players', '/admin/players', 'Search and edit accounts', 0],
            ['Economy', '/admin/economy', 'Stakes, fees, bonus', 0],
            ['Push message', '/admin/push', 'APK notifications', 0],
            ['Notices', '/admin/notices', 'In-app news / banner', 0],
            ['Support links', '/admin/support', 'Facebook and Telegram', 0],
            ['App update', '/admin/app-update', 'In-app APK update', 0],
            ['Coin shop', '/admin/coin-shop', 'Packs and discount', 0],
            ['SMS OTP', '/admin/otp-sms', 'Forgot password SMS', 0],
        ];
        echo '<section class="section"><h2>Quick actions</h2><div class="quick-grid">';
        foreach ($items as [$title, $href, $sub, $count]) {
            $cls = 'quick-card' . ($count > 0 ? ' has-pending' : '');
            echo '<a class="', $cls, '" href="', self::e($base . $href), '">',
                self::e($title);
            if ($count > 0) {
                echo '<small>', self::e($count), ' pending</small>';
            } else {
                echo '<small>', self::e($sub), '</small>';
            }
            echo '</a>';
        }
        echo '</div></section>';
    }

    private static function brandLogoUrl(): string
    {
        $file = dirname(__DIR__) . '/public/branding/logo.png';
        if (!is_file($file)) {
            return '';
        }
        return self::base() . '/branding/logo.png';
    }

    private static function pageLead(string $html): void
    {
        echo '<p class="page-lead">', $html, '</p></header>';
    }

    private static function endPageHead(): void
    {
        echo '</header>';
    }

    private static function backLink(string $href, string $label = '← Back'): void
    {
        echo '<p class="breadcrumb"><a class="btn ghost" href="', self::e(self::base() . $href), '">', self::e($label), '</a></p>';
    }

    private static function end(): never
    {
        echo '</main></div></body></html>';
        exit;
    }

    private static function fail(string $message, string $to): never
    {
        self::back($to, err: $message);
    }

    private static function gameLabel(string $key): string
    {
        return match ($key) {
            'poker' => 'Billiard Poker',
            'eight' => '8-Ball',
            'nine' => '9-Ball',
            'ten' => '10-Ball',
            'billiard' => 'Pool',
            'ludo2' => 'Ludo (2)',
            'ludo4' => 'Ludo (4)',
            'carrom' => 'Carrom',
            default => $key,
        };
    }

    private static function dashboard(): never
    {
        $stats = [
            'Players' => self::n('SELECT COUNT(*) AS n FROM users WHERE is_bot = 0'),
            'With a login' => self::n('SELECT COUNT(*) AS n FROM users WHERE is_guest = 0 AND is_bot = 0'),
            'New today' => self::n('SELECT COUNT(*) AS n FROM users WHERE created_at >= CURDATE() AND is_bot = 0'),
            'Matches today' => self::n('SELECT COUNT(*) AS n FROM games WHERE created_at >= CURDATE()'),
            'Matches running' => self::n("SELECT COUNT(*) AS n FROM games WHERE status = 'active'"),
            'Rooms waiting' => self::n("SELECT COUNT(*) AS n FROM rooms WHERE status = 'waiting'"),
            'Online now' => self::n("SELECT COUNT(DISTINCT user_id) AS n FROM auth_tokens WHERE last_used_at > DATE_SUB(NOW(), INTERVAL 3 MINUTE)"),
        ];
        $money = Db::one("SELECT COALESCE(SUM(CASE WHEN t.reason = 'buy_in' THEN -t.amount END), 0) AS bought,
                                 COALESCE(SUM(CASE WHEN t.reason = 'prize' THEN t.amount END), 0) AS paid
                          FROM wallet_tx t JOIN users u ON u.id = t.user_id WHERE t.currency = 'coins' AND u.is_bot = 0");
        $stats['Buy-ins collected'] = (int) $money['bought'];
        $stats['Prizes paid'] = (int) $money['paid'];
        $stats['House result'] = (int) $money['bought'] - (int) $money['paid'];
        $stats['Coins held'] = self::n('SELECT COALESCE(SUM(coins), 0) AS n FROM users WHERE is_bot = 0');
        $byGame = Db::all('SELECT game, COUNT(*) AS n FROM games WHERE created_at >= CURDATE() GROUP BY game');

        $live = Db::all("SELECT g.id, g.game, g.created_at, TIMESTAMPDIFF(MINUTE, g.created_at, NOW()) AS mins,
                                (SELECT GROUP_CONCAT(u.display_name ORDER BY gp.seat SEPARATOR ' vs ')
                                 FROM game_players gp JOIN users u ON u.id = gp.user_id WHERE gp.game_id = g.id) AS players
                         FROM games g WHERE g.status = 'active' ORDER BY g.id DESC LIMIT 50");
        $users = Db::all('SELECT id, display_name, phone, email, is_guest, banned, coins, gems, wins, games, created_at
                          FROM users WHERE is_bot = 0 ORDER BY id DESC LIMIT 15');
        $games = Db::all("SELECT g.id, g.game, g.status, g.created_at, g.finished_at, u.display_name AS winner
                          FROM games g LEFT JOIN users u ON u.id = g.winner_id ORDER BY g.id DESC LIMIT 15");
        $csrf = AdminAuth::csrfToken();
        $base = self::base();

        self::begin('Dashboard', 'dashboard');
        self::pageLead('Everything in one place — start with <b>Quick actions</b> below for daily approve and settings.');
        self::quickLinks();
        if (is_file(__DIR__ . '/ZiniPay.php') && !ZiniPay::publicEnabled()) {
            echo '<section class="section"><p class="muted"><strong>ZiniPay auto add is OFF.</strong> ',
                'Open <a href="', self::e($base), '/admin/zinipay">ZiniPay (auto)</a> or ',
                '<a href="', self::e($base), '/admin/deposits">Coin add</a> to enable API key.</p></section>';
        } elseif (!is_file(__DIR__ . '/ZiniPay.php')) {
            echo '<section class="section"><p class="muted"><strong>Missing ZiniPay.php on server.</strong> Upload <code>src/ZiniPay.php</code> from the latest backend package, then reload.</p></section>';
        }
        $unreadAlerts = AdminAlert::unreadCount();
        if ($unreadAlerts > 0) {
            echo '<section class="section"><h2>Unread signals (', self::e($unreadAlerts), ')</h2><p class="muted">Suspicious redeem, transfer abuse, or game integrity.</p>',
                '<p><a class="btn" href="', self::e($base), '/admin/alerts">Open alerts</a></p></section>';
        }
        echo '<section class="section"><h2>Key metrics</h2><div class="stats">';
        foreach ($stats as $label => $value) {
            echo '<div class="stat"><b>', self::e($value), '</b><span>', self::e($label), '</span></div>';
        }
        echo '</div></section>';
        if ($byGame !== []) {
            echo '<section class="section"><h2>Matches today by game</h2><div class="stats">';
            foreach ($byGame as $g) {
                echo '<div class="stat"><b>', self::e($g['n']), '</b><span>', self::e(self::gameLabel((string) $g['game'])), '</span></div>';
            }
            echo '</div></section>';
        }

        echo '<section class="section"><h2>Live now</h2>', self::tableScrollOpen(),
            '<table><tr><th>Game ID<th>Type<th>Players<th>Started<th>Running</tr>';
        foreach ($live as $g) {
            echo '<tr><td><a href="', self::e($base), '/admin/match?id=', self::e($g['id']), '">', self::e($g['id']), '</a>',
                '<td>', self::e(self::gameLabel((string) $g['game'])),
                '<td>', self::e($g['players'] ?? ''), '<td>', self::e($g['created_at']),
                '<td>', self::e((int) $g['mins']), ' min</tr>';
        }
        if ($live === []) {
            echo '<tr><td colspan="5" class="muted">No matches running.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), '</section>';

        echo '<section class="section"><h2>Latest players</h2>', self::tableScrollOpen(),
            '<table><tr><th>ID<th>Name<th>Mobile<th>Coins<th>Gems<th>Wins / games<th>Joined<th></tr>';
        foreach ($users as $u) {
            echo self::playerRow($u, $csrf, '/admin');
        }
        if ($users === []) {
            echo '<tr><td colspan="8" class="muted">No players yet.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(),
            '<p class="link-row"><a class="btn ghost" href="', self::e($base), '/admin/players">All players →</a></p></section>';

        echo '<section class="section"><h2>Latest matches</h2>', self::matchTable($games),
            '<p class="link-row"><a class="btn ghost" href="', self::e($base), '/admin/matches">All matches →</a></p></section>';
        $pending = self::pendingNavCounts();
        if ($pending['deposits'] > 0 || $pending['redeems'] > 0) {
            echo '<section class="section"><h2>Needs action</h2><div class="stats">';
            if ($pending['deposits'] > 0) {
                echo '<div class="stat accent"><b>', self::e($pending['deposits']), '</b><span>coin add pending</span></div>';
            }
            if ($pending['redeems'] > 0) {
                echo '<div class="stat accent"><b>', self::e($pending['redeems']), '</b><span>redeem pending</span></div>';
            }
            echo '</div><p class="link-row">';
            if ($pending['deposits'] > 0) {
                echo '<a class="btn" href="', self::e($base), '/admin/deposits?status=pending">Review coin add</a> ';
            }
            if ($pending['redeems'] > 0) {
                echo '<a class="btn" href="', self::e($base), '/admin/redeems?status=pending">Review redeem</a>';
            }
            echo '</p></section>';
        }
        self::end();
    }

    /** @param array<string,mixed> $u */
    private static function loginLabel(array $u): string
    {
        if (self::on($u['is_guest'])) {
            return 'guest';
        }
        $phone = $u['phone'] ?? null;
        if ($phone !== null && $phone !== '') {
            return Phone::display((string) $phone);
        }
        return (string) ($u['email'] ?? '');
    }

    /** @param array<string,mixed> $u */
    private static function playerRow(array $u, string $csrf, string $next): string
    {
        $base = self::base();
        $id = (int) $u['id'];
        $html = '<tr><td>' . self::e($id)
            . '<td><a href="' . self::e($base) . '/admin/player?id=' . self::e($id) . '">' . self::e($u['display_name']) . '</a> '
            . (self::on($u['banned']) ? '<span class="pill bad">suspended</span>' : '')
            . '<td>' . self::e(self::loginLabel($u))
            . '<td>' . self::e($u['coins']) . '<td>' . self::e($u['gems'])
            . '<td>' . self::e($u['wins']) . ' / ' . self::e($u['games'])
            . '<td>' . self::e($u['created_at'])
            . '<td><a class="btn ghost" href="' . self::e($base) . '/admin/player?id=' . self::e($id) . '">Edit</a> '
            . '<form class="inline" method="post" action="' . self::e($base) . '/admin/ban">' . self::csrfField($csrf)
            . '<input type="hidden" name="id" value="' . self::e($id) . '">'
            . '<input type="hidden" name="next" value="' . self::e($next) . '">'
            . '<input type="hidden" name="banned" value="' . (self::on($u['banned']) ? '0' : '1') . '">'
            . '<button class="' . (self::on($u['banned']) ? 'ok' : 'danger') . '">' . (self::on($u['banned']) ? 'Restore' : 'Suspend') . '</button></form></tr>';
        return $html;
    }

    /** @param list<array<string,mixed>> $games */
    private static function matchTable(array $games): string
    {
        $base = self::base();
        $html = '<table><tr><th>ID<th>Game<th>Status<th>Winner<th>Started<th>Finished</tr>';
        foreach ($games as $g) {
            $html .= '<tr><td><a href="' . self::e($base) . '/admin/match?id=' . self::e($g['id']) . '">' . self::e($g['id']) . '</a>'
                . '<td>' . self::e(self::gameLabel((string) $g['game']))
                . '<td>' . self::e($g['status'])
                . '<td>' . self::e($g['winner'] ?? '')
                . '<td>' . self::e($g['created_at'])
                . '<td>' . self::e($g['finished_at'] ?? '') . '</tr>';
        }
        if ($games === []) {
            $html .= '<tr><td colspan="6" class="muted">No matches yet.</td></tr>';
        }
        return self::tableScrollOpen() . $html . '</table>' . self::tableScrollClose();
    }

    private static function playersPage(): never
    {
        $q = trim((string) ($_GET['q'] ?? ''));
        $q = str_replace(['%', '_'], '', $q);
        $page = self::pageOf('page');
        $where = 'is_bot = 0';
        $params = [];
        if ($q !== '') {
            $where .= ' AND (display_name LIKE ? OR IFNULL(phone, \'\') LIKE ? OR IFNULL(email, \'\') LIKE ?';
            $like = '%' . $q . '%';
            $params = [$like, $like, $like];
            if (ctype_digit($q)) {
                $where .= ' OR id = ?';
                $params[] = (int) $q;
            }
            $where .= ')';
        }
        $total = self::n("SELECT COUNT(*) AS n FROM users WHERE $where", $params);
        $rows = Db::all(
            "SELECT id, display_name, phone, email, is_guest, banned, coins, gems, wins, games, created_at
             FROM users WHERE $where ORDER BY id DESC LIMIT " . self::PER . ' OFFSET ' . (($page - 1) * self::PER),
            $params
        );
        $csrf = AdminAuth::csrfToken();
        $keep = $q === '' ? [] : ['q' => $q];
        $next = '/admin/players' . ($q === '' ? '' : '?q=' . rawurlencode($q));

        self::begin('Players', 'players');
        self::pageLead('Search, edit profiles, adjust Pico coin / gems, suspend accounts.');
        echo '<div class="search-card"><form class="row" method="get" action="', self::e(self::base()), '/admin/players">',
            '<label>Search name, mobile or id<input name="q" value="', self::e($q), '" placeholder="Search players"></label>',
            '<button>Search</button></form></div>',
            '<section class="section"><h2>Results</h2><p class="muted">', self::e($total), ' player(s).</p>',
            self::tableScrollOpen(),
            '<table><tr><th>ID<th>Name<th>Mobile<th>Coins<th>Gems<th>Wins / games<th>Joined<th></tr>';
        foreach ($rows as $u) {
            echo self::playerRow($u, $csrf, $next);
        }
        if ($rows === []) {
            echo '<tr><td colspan="8" class="muted">No players match.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), self::pager('page', $page, $total, $keep), '</section>';
        self::end();
    }

    private static function playerPage(string $csrf, int $id): never
    {
        $u = Db::one('SELECT * FROM users WHERE id = ? AND is_bot = 0', [$id]);
        $base = self::base();
        self::begin($u === null ? 'Player' : (string) $u['display_name'], 'players');
        if ($u === null) {
            self::endPageHead();
            self::backLink('/admin/players', '← All players');
            echo '<div class="card">Player not found.</div>';
            self::end();
        }
        self::pageLead(self::e(self::loginLabel($u)) . ' · joined ' . self::e($u['created_at']));
        self::backLink('/admin/players', '← All players');

        echo '<section class="section"><div class="stats">',
            '<div class="stat"><b>', self::e($u['coins']), '</b><span>coins</span></div>',
            '<div class="stat"><b>', self::e($u['gems']), '</b><span>gems</span></div>',
            '<div class="stat"><b>', self::e((int) $u['xp']), '</b><span>xp</span></div>',
            '<div class="stat"><b>', self::e($u['wins']), ' / ', self::e($u['games']), '</b><span>wins / games</span></div>',
            '<div class="stat"><b>', self::on($u['banned']) ? 'Suspended' : 'Active', '</b><span>', self::e(self::on($u['is_guest']) ? 'guest' : 'account'), '</span></div>',
            '<div class="stat"><b>', self::e($u['referral_code'] ?? '—'), '</b><span>invite code</span></div>',
            '</div></section>';
        if ($u['referred_by'] !== null) {
            $inviter = Db::one('SELECT id, display_name FROM users WHERE id = ?', [(int) $u['referred_by']]);
            echo '<p>Invited by ';
            if ($inviter !== null) {
                echo '<a href="', self::e($base), '/admin/player?id=', self::e($inviter['id']), '">', self::e($inviter['display_name']), '</a>';
            } else {
                echo 'player ', self::e($u['referred_by']);
            }
            echo '.</p>';
        }
        echo '<section class="section">', self::referralBlock($id, $base), '</section>';

        echo '<section class="section"><h2>Profile</h2><div class="card"><form method="post" action="', self::e($base), '/admin/player/save">',
            self::csrfField($csrf), '<input type="hidden" name="id" value="', self::e($id), '"><div class="grid">',
            '<label>Name<input name="display_name" maxlength="24" required value="', self::e($u['display_name']), '"></label>',
            '<label>Mobile (+880)<input name="phone" value="', self::e(isset($u['phone']) && $u['phone'] !== null && $u['phone'] !== '' ? substr((string) $u['phone'], 3) : ''), '" placeholder="10 digits, empty = guest"></label>',
            '<label>Avatar<select name="avatar">';
        for ($i = 1; $i <= 6; $i++) {
            $av = 'asset:avatar_' . $i;
            echo '<option value="', $av, '"', $u['avatar'] === $av ? ' selected' : '', '>Avatar ', $i, '</option>';
        }
        if (!str_starts_with((string) $u['avatar'], 'asset:avatar_')) {
            echo '<option value="', self::e($u['avatar']), '" selected>Keep uploaded photo</option>';
        }
        echo '</select></label>',
            '<label>Table skin<input name="table_skin" maxlength="32" value="', self::e($u['table_skin']), '"></label>',
            '<label>Cue<select name="cue">';
        foreach (Economy::CUES as $cueId => $cue) {
            echo '<option value="', self::e($cueId), '"', $u['cue'] === $cueId ? ' selected' : '', '>', self::e($cue['name']), '</option>';
        }
        echo '</select></label>',
            '<label>XP<input type="number" min="0" name="xp" value="', self::e((int) $u['xp']), '"></label>',
            '<label>Wins<input type="number" min="0" name="wins" value="', self::e((int) $u['wins']), '"></label>',
            '<label>Games<input type="number" min="0" name="games" value="', self::e((int) $u['games']), '"></label>',
            '<label>New password<input type="text" name="new_password" autocomplete="off" placeholder="Leave empty to keep"></label>',
            '<label>Nickname chosen<select name="name_set"><option value="1"', self::on($u['name_set']) ? ' selected' : '', '>Yes</option>',
            '<option value="0"', self::on($u['name_set']) ? '' : ' selected', '>No</option></select></label>',
            '</div><p></p><button>Save profile</button></form></div></section>';

        echo '<section class="section"><h2>Balance</h2><p class="hint">Add, subtract, or set exact coins or gems. Logged in wallet history; balance cannot go below zero.</p><div class="card"><div class="row">';
        foreach (['add' => 'Add', 'subtract' => 'Subtract', 'set' => 'Set exact'] as $mode => $label) {
            echo '<form method="post" action="', self::e($base), '/admin/adjust">', self::csrfField($csrf),
                '<input type="hidden" name="id" value="', self::e($id), '">',
                '<input type="hidden" name="mode" value="', $mode, '">',
                '<label>', self::e($label), ' <input type="number" name="amount" required style="width:120px"></label> ',
                '<label>Currency <select name="currency"><option value="coins">coins</option><option value="gems">gems</option></select></label> ',
                '<label>Reason <input name="reason" maxlength="30" placeholder="support"></label> ',
                '<button>', self::e($label), '</button></form>';
        }
        echo '</div></div></section>';

        echo '<section class="section"><div class="row"><form method="post" action="', self::e($base), '/admin/ban">', self::csrfField($csrf),
            '<input type="hidden" name="id" value="', self::e($id), '">',
            '<input type="hidden" name="banned" value="', self::on($u['banned']) ? '0' : '1', '">',
            '<button class="', self::on($u['banned']) ? 'ok' : 'danger', '">', self::on($u['banned']) ? 'Restore player' : 'Suspend player', '</button></form>',
            '<form method="post" action="', self::e($base), '/admin/player/signout">', self::csrfField($csrf),
            '<input type="hidden" name="id" value="', self::e($id), '"><button class="ghost">Sign out of all devices</button></form></div></section>';

        $wpage = self::pageOf('wpage');
        $wtotal = self::n('SELECT COUNT(*) AS n FROM wallet_tx WHERE user_id = ?', [$id]);
        $tx = Db::all(
            'SELECT created_at, currency, amount, balance_after, reason, room_id FROM wallet_tx
             WHERE user_id = ? ORDER BY id DESC LIMIT ' . self::PER . ' OFFSET ' . (($wpage - 1) * self::PER),
            [$id]
        );
        echo '<section class="section"><h2>Wallet history</h2><p class="muted">', self::e($wtotal), ' movement(s), newest first.</p>',
            self::tableScrollOpen(),
            '<table><tr><th>When<th>Currency<th>Amount<th>Balance after<th>Reason<th>Room</tr>';
        foreach ($tx as $t) {
            $amt = (int) $t['amount'];
            echo '<tr><td>', self::e($t['created_at']), '<td>', self::e($t['currency']),
                '<td class="', $amt >= 0 ? 'good' : 'bad', '">', $amt >= 0 ? '+' : '', self::e($amt),
                '<td>', self::e($t['balance_after']), '<td>', self::e($t['reason']),
                '<td>', self::e($t['room_id'] ?? ''), '</tr>';
        }
        if ($tx === []) {
            echo '<tr><td colspan="6" class="muted">No wallet movements yet.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), self::pager('wpage', $wpage, $wtotal, ['id' => $id, 'mpage' => self::pageOf('mpage')]), '</section>';

        $mpage = self::pageOf('mpage');
        $mtotal = self::n('SELECT COUNT(*) AS n FROM match_results WHERE user_id = ?', [$id]);
        $matches = Db::all(
            'SELECT created_at, game, mode, won, coins_delta, stake, prize, game_id FROM match_results
             WHERE user_id = ? ORDER BY id DESC LIMIT ' . self::PER . ' OFFSET ' . (($mpage - 1) * self::PER),
            [$id]
        );
        echo '<section class="section"><h2>Match history</h2><p class="muted">', self::e($mtotal), ' match(es) across pool, ludo and carrom.</p>',
            self::tableScrollOpen(),
            '<table><tr><th>When<th>Game<th>Mode<th>Result<th>Coins<th>Stake<th>Prize<th>Match</tr>';
        foreach ($matches as $m) {
            $delta = (int) $m['coins_delta'];
            echo '<tr><td>', self::e($m['created_at']), '<td>', self::e(self::gameLabel((string) $m['game'])),
                '<td>', self::e($m['mode']),
                '<td class="', self::on($m['won']) ? 'good' : '', '">', self::on($m['won']) ? 'WIN' : 'loss',
                '<td class="', $delta >= 0 ? 'good' : 'bad', '">', $delta >= 0 ? '+' : '', self::e($delta),
                '<td>', self::e($m['stake']), '<td>', self::e($m['prize']), '<td>';
            if ($m['game_id'] !== null) {
                echo '<a href="', self::e($base), '/admin/match?id=', self::e($m['game_id']), '">', self::e($m['game_id']), '</a>';
            }
            echo '</tr>';
        }
        if ($matches === []) {
            echo '<tr><td colspan="8" class="muted">No matches yet.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), self::pager('mpage', $mpage, $mtotal, ['id' => $id, 'wpage' => $wpage]), '</section>';
        self::end();
    }

    private static function matchesPage(): never
    {
        $game = (string) ($_GET['game'] ?? '');
        $allowed = ['poker', 'eight', 'nine', 'ten', 'ludo2', 'ludo4', 'carrom'];
        if (!in_array($game, $allowed, true)) {
            $game = '';
        }
        $page = self::pageOf('page');
        $where = '1=1';
        $params = [];
        if ($game !== '') {
            $where = 'g.game = ?';
            $params[] = $game;
        }
        $total = self::n("SELECT COUNT(*) AS n FROM games g WHERE $where", $params);
        $rows = Db::all(
            "SELECT g.id, g.game, g.status, g.created_at, g.finished_at, u.display_name AS winner
             FROM games g LEFT JOIN users u ON u.id = g.winner_id
             WHERE $where ORDER BY g.id DESC LIMIT " . self::PER . ' OFFSET ' . (($page - 1) * self::PER),
            $params
        );
        $base = self::base();
        self::begin('Matches', 'matches');
        self::pageLead('Browse finished and active games. Filter by game type.');
        echo '<div class="filters"><a class="', $game === '' ? 'on' : '', '" href="', self::e($base), '/admin/matches">All</a>';
        foreach ($allowed as $key) {
            echo '<a class="', $game === $key ? 'on' : '', '" href="', self::e($base), '/admin/matches?game=', self::e($key), '">',
                self::e(self::gameLabel($key)), '</a>';
        }
        echo '</div><section class="section"><p class="muted">', self::e($total), ' match(es).</p>', self::matchTable($rows),
            self::pager('page', $page, $total, $game === '' ? [] : ['game' => $game]), '</section>';
        self::end();
    }

    private static function matchPage(int $id): never
    {
        $g = Db::one(
            'SELECT g.*, r.code, r.stake, r.fee, r.prize, r.level, u.display_name AS winner_name
             FROM games g LEFT JOIN rooms r ON r.id = g.room_id LEFT JOIN users u ON u.id = g.winner_id
             WHERE g.id = ?',
            [$id]
        );
        $base = self::base();
        self::begin($g === null ? 'Match' : 'Match ' . $id, 'matches');
        if ($g === null) {
            self::endPageHead();
            self::backLink('/admin/matches', '← All matches');
            echo '<div class="card">Match not found.</div>';
            self::end();
        }
        self::pageLead(self::e(self::gameLabel((string) $g['game'])) . ' · ' . self::e($g['status']));
        self::backLink('/admin/matches', '← All matches');
        echo '<section class="section"><div class="stats">',
            '<div class="stat"><b>', self::e(self::gameLabel((string) $g['game'])), '</b><span>game</span></div>',
            '<div class="stat"><b>', self::e($g['status']), '</b><span>status</span></div>',
            '<div class="stat"><b>', self::e($g['winner_name'] ?? '—'), '</b><span>winner</span></div>',
            '<div class="stat"><b>', self::e($g['stake']), '</b><span>stake</span></div>',
            '<div class="stat"><b>', self::e($g['prize']), '</b><span>prize</span></div>',
            '<div class="stat"><b>', self::e($g['code'] ?? '—'), '</b><span>room code</span></div>',
            '</div></section>';
        $players = Db::all(
            'SELECT gp.seat, u.id, u.display_name FROM game_players gp JOIN users u ON u.id = gp.user_id WHERE gp.game_id = ? ORDER BY gp.seat',
            [$id]
        );
        echo '<section class="section"><h2>Players</h2>', self::tableScrollOpen(),
            '<table><tr><th>Seat<th>Player</tr>';
        foreach ($players as $p) {
            echo '<tr><td>', self::e($p['seat']), '<td><a href="', self::e($base), '/admin/player?id=', self::e($p['id']), '">',
                self::e($p['display_name']), '</a></tr>';
        }
        echo '</table>', self::tableScrollClose(), '</section>';
        $page = self::pageOf('page');
        $total = self::n('SELECT COUNT(*) AS n FROM game_shots WHERE game_id = ?', [$id]);
        $shots = Db::all(
            'SELECT s.seq, s.created_at, s.user_id, u.display_name, s.result FROM game_shots s
             LEFT JOIN users u ON u.id = s.user_id WHERE s.game_id = ? ORDER BY s.seq DESC LIMIT ' . self::PER . ' OFFSET ' . (($page - 1) * self::PER),
            [$id]
        );
        echo '<section class="section"><h2>Shot history</h2><p class="muted">', self::e($total), ' shot(s).</p>',
            self::tableScrollOpen(),
            '<table><tr><th>#<th>When<th>Player<th>Result</tr>';
        foreach ($shots as $s) {
            $result = (string) ($s['result'] ?? '');
            if (strlen($result) > 180) {
                $result = substr($result, 0, 180) . '…';
            }
            echo '<tr><td>', self::e($s['seq']), '<td>', self::e($s['created_at']), '<td>';
            if ($s['user_id'] !== null) {
                echo '<a href="', self::e($base), '/admin/player?id=', self::e($s['user_id']), '">', self::e($s['display_name'] ?? $s['user_id']), '</a>';
            }
            echo '<td>', self::e($result), '</tr>';
        }
        if ($shots === []) {
            echo '<tr><td colspan="4" class="muted">No shots logged.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), self::pager('page', $page, $total, ['id' => $id]), '</section>';
        self::end();
    }

    private static function walletPage(): never
    {
        $page = self::pageOf('page');
        $currency = ($_GET['currency'] ?? '') === 'gems' ? 'gems' : (($_GET['currency'] ?? '') === 'coins' ? 'coins' : '');
        $where = '1=1';
        $params = [];
        if ($currency !== '') {
            $where = 't.currency = ?';
            $params[] = $currency;
        }
        $total = self::n("SELECT COUNT(*) AS n FROM wallet_tx t WHERE $where", $params);
        $rows = Db::all(
            "SELECT t.created_at, t.user_id, u.display_name, t.currency, t.amount, t.balance_after, t.reason, t.room_id
             FROM wallet_tx t JOIN users u ON u.id = t.user_id
             WHERE $where ORDER BY t.id DESC LIMIT " . self::PER . ' OFFSET ' . (($page - 1) * self::PER),
            $params
        );
        $base = self::base();
        self::begin('Wallet history', 'wallet');
        self::pageLead('Every Pico coin and gem movement across all players.');
        echo '<div class="filters">',
            '<a class="', $currency === '' ? 'on' : '', '" href="', self::e($base), '/admin/wallet">All</a>',
            '<a class="', $currency === 'coins' ? 'on' : '', '" href="', self::e($base), '/admin/wallet?currency=coins">Coins</a>',
            '<a class="', $currency === 'gems' ? 'on' : '', '" href="', self::e($base), '/admin/wallet?currency=gems">Gems</a>',
            '</div><section class="section"><p class="muted">', self::e($total), ' movement(s).</p>',
            self::tableScrollOpen(),
            '<table><tr><th>When<th>Player<th>Currency<th>Amount<th>Balance after<th>Reason<th>Room</tr>';
        foreach ($rows as $t) {
            $amt = (int) $t['amount'];
            echo '<tr><td>', self::e($t['created_at']),
                '<td><a href="', self::e($base), '/admin/player?id=', self::e($t['user_id']), '">', self::e($t['display_name']), '</a>',
                '<td>', self::e($t['currency']),
                '<td class="', $amt >= 0 ? 'good' : 'bad', '">', $amt >= 0 ? '+' : '', self::e($amt),
                '<td>', self::e($t['balance_after']), '<td>', self::e($t['reason']), '<td>', self::e($t['room_id'] ?? ''), '</tr>';
        }
        if ($rows === []) {
            echo '<tr><td colspan="7" class="muted">No wallet movements yet.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), self::pager('page', $page, $total, $currency === '' ? [] : ['currency' => $currency]), '</section>';
        self::end();
    }

    /** Counts, today, this month, and the people one player invited. */
    private static function referralBlock(int $id, string $base): string
    {
        $report = Economy::referralReport($id);
        $html = '<h2>Referrals</h2><div class="stats">'
            . '<div class="stat"><b>' . self::e($report['invited']) . '</b><span>people invited</span></div>'
            . '<div class="stat"><b>' . self::e($report['earnedToday']) . '</b><span>earned today</span></div>'
            . '<div class="stat"><b>' . self::e($report['earnedMonth']) . '</b><span>earned this month</span></div>'
            . '<div class="stat"><b>' . self::e($report['earned']) . '</b><span>earned in total</span></div>'
            . '</div>';
        $html .= self::tableScrollOpen() . '<table><tr><th>Player<th>Joined<th>Games<th>Earned from them</tr>';
        foreach ($report['people'] as $p) {
            $html .= '<tr><td><a href="' . self::e($base) . '/admin/player?id=' . self::e($p['id']) . '">' . self::e($p['name']) . '</a>'
                . ($p['guest'] ? ' <span class="pill">guest</span>' : '')
                . '<td>' . self::e($p['joined'])
                . '<td>' . self::e($p['games'])
                . '<td>' . self::e($p['earned']) . '</tr>';
        }
        if ($report['people'] === []) {
            $html .= '<tr><td colspan="4" class="muted">Nobody has used this invite code yet.</td></tr>';
        }
        return $html . '</table>' . self::tableScrollClose();
    }

    private static function referralsPage(string $csrf): never
    {
        $page = self::pageOf('page');
        $total = self::n(
            "SELECT COUNT(*) AS n FROM (
                SELECT u.id FROM users u
                WHERE u.is_bot = 0 AND (
                    EXISTS (SELECT 1 FROM users c WHERE c.referred_by = u.id)
                    OR EXISTS (SELECT 1 FROM wallet_tx t WHERE t.user_id = u.id AND t.reason = 'referral')
                )
            ) x"
        );
        $rows = Db::all(
            "SELECT u.id, u.display_name, u.referral_code,
                    (SELECT COUNT(*) FROM users c WHERE c.referred_by = u.id) AS invited,
                    (SELECT COALESCE(SUM(amount), 0) FROM wallet_tx t WHERE t.user_id = u.id AND t.reason = 'referral' AND t.created_at >= CURDATE()) AS today,
                    (SELECT COALESCE(SUM(amount), 0) FROM wallet_tx t WHERE t.user_id = u.id AND t.reason = 'referral' AND t.created_at >= DATE_FORMAT(NOW(), '%Y-%m-01')) AS month,
                    (SELECT COALESCE(SUM(amount), 0) FROM wallet_tx t WHERE t.user_id = u.id AND t.reason = 'referral') AS earned
             FROM users u
             WHERE u.is_bot = 0 AND (
                EXISTS (SELECT 1 FROM users c WHERE c.referred_by = u.id)
                OR EXISTS (SELECT 1 FROM wallet_tx t WHERE t.user_id = u.id AND t.reason = 'referral')
             )
             ORDER BY invited DESC, earned DESC, u.id DESC
             LIMIT " . self::PER . ' OFFSET ' . (($page - 1) * self::PER)
        );
        $base = self::base();
        $today = self::n("SELECT COALESCE(SUM(amount), 0) AS n FROM wallet_tx WHERE reason = 'referral' AND created_at >= CURDATE()");
        $month = self::n("SELECT COALESCE(SUM(amount), 0) AS n FROM wallet_tx WHERE reason = 'referral' AND created_at >= DATE_FORMAT(NOW(), '%Y-%m-01')");
        $invited = self::n('SELECT COUNT(*) AS n FROM users WHERE referred_by IS NOT NULL AND is_bot = 0');
        $percent = (int) Economy::config()['referralPercent'];
        $fee = (int) Economy::config()['rakePercent'];
        self::begin('Referrals', 'referrals');
        self::pageLead('Invite codes, commission on staked matches, and referral Pico coin earnings.');
        echo '<section class="section"><h2>Commission setting</h2>',
            '<p class="hint">When someone who used a friend\'s code plays a <b>staked</b> match, the inviter gets this % of the stake. ',
            'Example: 1% on a 1000 stake = 10 coins. Cannot exceed the house fee (currently ', self::e($fee), '%).</p>',
            '<div class="card"><form class="row" method="post" action="', self::e($base), '/admin/referral">', self::csrfField($csrf),
            '<label>Commission (% of stake)<input type="number" name="percent" min="0" max="50" step="1" required value="', self::e($percent), '"></label>',
            '<button type="submit">Save commission</button></form></div></section>',
            '<section class="section"><h2>Overview</h2><div class="stats">',
            '<div class="stat"><b>', self::e($percent), '%</b><span>current commission</span></div>',
            '<div class="stat"><b>', self::e($total), '</b><span>people who invited someone</span></div>',
            '<div class="stat"><b>', self::e($invited), '</b><span>joined with a code</span></div>',
            '<div class="stat"><b>', self::e($today), '</b><span>coins paid today</span></div>',
            '<div class="stat"><b>', self::e($month), '</b><span>coins paid this month</span></div>',
            '</div></section>',
            '<section class="section"><h2>Top inviters</h2>',
            self::tableScrollOpen(),
            '<table><tr><th>Player<th>Code<th>Invited<th>Today<th>This month<th>Total</tr>';
        foreach ($rows as $r) {
            echo '<tr><td><a href="', self::e($base), '/admin/player?id=', self::e($r['id']), '">', self::e($r['display_name']), '</a>',
                '<td>', self::e($r['referral_code'] ?? ''),
                '<td>', self::e($r['invited']),
                '<td>', self::e($r['today']),
                '<td>', self::e($r['month']),
                '<td>', self::e($r['earned']), '</tr>';
        }
        if ($rows === []) {
            echo '<tr><td colspan="6" class="muted">No invites yet.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), self::pager('page', $page, $total), '</section>';
        self::end();
    }

    private static function saveCoinShopGlobal(): never
    {
        $c = CoinShop::config();
        $c['globalDiscountPercent'] = (int) ($_POST['globalDiscountPercent'] ?? 0);
        try {
            CoinShop::save($c);
        } catch (ApiError $e) {
            self::fail($e->getMessage(), '/admin/coin-shop');
        }
        self::back('/admin/coin-shop', 'Coin shop discount saved.');
    }

    private static function saveCoinShopPack(): never
    {
        $c = CoinShop::config();
        $pack = [
            'id' => strtolower(trim((string) ($_POST['id'] ?? ''))),
            'name' => trim((string) ($_POST['name'] ?? '')),
            'coins' => (int) ($_POST['coins'] ?? 0),
            'discountPercent' => (int) ($_POST['discountPercent'] ?? 0),
            'priceCoins' => (int) ($_POST['priceCoins'] ?? 0),
            'active' => ($_POST['active'] ?? '0') === '1',
            'sort' => (int) ($_POST['sort'] ?? 0),
        ];
        $packs = $c['packs'];
        $found = false;
        foreach ($packs as $i => $p) {
            if ($p['id'] === $pack['id']) {
                $packs[$i] = $pack;
                $found = true;
                break;
            }
        }
        if (!$found) {
            $packs[] = $pack;
        }
        $c['packs'] = $packs;
        try {
            CoinShop::save($c);
        } catch (ApiError $e) {
            self::fail($e->getMessage(), '/admin/coin-shop');
        }
        self::back('/admin/coin-shop', 'Coin pack saved.');
    }

    private static function deleteCoinShopPack(): never
    {
        $id = strtolower(trim((string) ($_POST['id'] ?? '')));
        $c = CoinShop::config();
        $c['packs'] = array_values(array_filter($c['packs'], static fn (array $p): bool => $p['id'] !== $id));
        try {
            CoinShop::save($c);
        } catch (ApiError $e) {
            self::fail($e->getMessage(), '/admin/coin-shop');
        }
        self::back('/admin/coin-shop', 'Coin pack removed.');
    }

    private static function saveOtpSms(): never
    {
        $raw = [
            'enabled' => ($_POST['enabled'] ?? '0') === '1',
            'otpDigits' => (int) ($_POST['otpDigits'] ?? 6),
            'validMinutes' => (int) ($_POST['validMinutes'] ?? 15),
            'maxPerPhonePerHour' => (int) ($_POST['maxPerPhonePerHour'] ?? 3),
            'maxPerIpPerHour' => (int) ($_POST['maxPerIpPerHour'] ?? 10),
            'delivery' => (string) ($_POST['delivery'] ?? 'log'),
            'messageTemplate' => trim((string) ($_POST['messageTemplate'] ?? '')),
            'httpUrl' => trim((string) ($_POST['httpUrl'] ?? '')),
            'httpApiKey' => trim((string) ($_POST['httpApiKey'] ?? '')),
            'httpBodyTemplate' => trim((string) ($_POST['httpBodyTemplate'] ?? '')),
        ];
        if ($raw['delivery'] === 'http' && $raw['httpUrl'] === '') {
            self::fail('Set the SMS gateway URL or choose Log only.', '/admin/otp-sms');
        }
        OtpSms::save($raw);
        self::back('/admin/otp-sms', 'SMS OTP settings saved.');
    }

    private static function otpSmsPage(string $csrf): never
    {
        $base = self::base();
        $c = OtpSms::config();
        self::begin('SMS OTP (forgot password)', 'otp-sms');
        self::pageLead('Forgot password only — sign-up does not send OTP. After OTP the player sets a new password in the app.');
        echo '<section class="section"><div class="card"><form method="post" action="', self::e($base), '/admin/otp-sms">', self::csrfField($csrf),
            '<label class="check"><input type="checkbox" name="enabled" value="1"', $c['enabled'] ? ' checked' : '', '> Enable forgot-password SMS</label>',
            '<div class="grid">',
            '<label>OTP digits (4–8)<input type="number" name="otpDigits" min="4" max="8" value="', self::e($c['otpDigits']), '"></label>',
            '<label>Valid (minutes)<input type="number" name="validMinutes" min="5" max="60" value="', self::e($c['validMinutes']), '"></label>',
            '<label>Max SMS / phone / hour<input type="number" name="maxPerPhonePerHour" min="1" max="20" value="', self::e($c['maxPerPhonePerHour']), '"></label>',
            '<label>Max SMS / IP / hour<input type="number" name="maxPerIpPerHour" min="1" max="100" value="', self::e($c['maxPerIpPerHour']), '"></label>',
            '</div>',
            '<label>SMS text (must include <code>{code}</code> and may use <code>{minutes}</code>)',
            '<textarea name="messageTemplate" rows="3">', self::e($c['messageTemplate']), '</textarea></label>',
            '<label>Delivery<select name="delivery">',
            '<option value="log"', $c['delivery'] === 'log' ? ' selected' : '', '>Log only (development — OTP in server error log)</option>',
            '<option value="http"', $c['delivery'] === 'http' ? ' selected' : '', '>HTTP SMS gateway</option>',
            '</select></label>',
            '<label>Gateway URL<input name="httpUrl" value="', self::e($c['httpUrl']), '" placeholder="https://sms-provider.example/send"></label>',
            '<label>Gateway API key (optional Bearer token)<input name="httpApiKey" value="', self::e($c['httpApiKey']), '" autocomplete="off"></label>',
            '<label>Gateway JSON body (<code>{phone}</code> = 8801…, <code>{message}</code> = full SMS text)',
            '<textarea name="httpBodyTemplate" rows="4" spellcheck="false">', self::e($c['httpBodyTemplate']), '</textarea></label>',
            '<p class="muted">For local tests, set <code>SMS_LOG</code> in .env to a file path — OTP is appended there and overrides delivery.</p>',
            '<button>Save OTP settings</button></form></div></section>';
        self::end();
    }

    private static function saveRedeemConfig(): never
    {
        Redeem::save([
            'enabled' => ($_POST['enabled'] ?? '0') === '1',
            'minCoins' => (int) ($_POST['minCoins'] ?? 1000),
            'maxCoins' => (int) ($_POST['maxCoins'] ?? 200000),
            'maxPendingPerUser' => (int) ($_POST['maxPendingPerUser'] ?? 2),
            'coinPerBdt' => (int) ($_POST['coinPerBdt'] ?? 1),
        ]);
        self::back('/admin/redeems', 'Redeem settings saved.');
    }

    private static function reviewRedeem(bool $approve): never
    {
        $id = (int) ($_POST['id'] ?? 0);
        $note = trim((string) ($_POST['note'] ?? ''));
        $back = '/admin/redeems';
        try {
            if ($approve) {
                Redeem::approve($id, $note);
            } else {
                if ($note === '') {
                    self::fail('Add a short reason when rejecting (shown to the player).', $back);
                }
                Redeem::reject($id, $note);
            }
        } catch (ApiError $e) {
            self::fail($e->getMessage(), $back);
        }
        self::back($back, $approve ? 'Redeem request approved.' : 'Redeem request rejected.');
    }

    private static function redeemsPage(string $csrf): never
    {
        $base = self::base();
        $status = (string) ($_GET['status'] ?? 'pending');
        if (!in_array($status, ['pending', 'approved', 'rejected', 'cancelled', 'all'], true)) {
            $status = 'pending';
        }
        $where = $status === 'all' ? '1=1' : 'r.status = ' . Db::pdo()->quote($status);
        $rows = Db::all(
            "SELECT r.*, u.display_name, u.phone, u.coins AS balance_now
             FROM redeem_requests r JOIN users u ON u.id = r.user_id
             WHERE $where ORDER BY r.id DESC LIMIT 100"
        );
        $c = Redeem::config();
        self::begin('Redeem requests', 'redeems');
        self::pageLead('Cash out to bKash / Nagad / Rocket. Coins are held on submit; reject refunds the player.');
        echo '<div class="filters">',
            '<a class="', $status === 'pending' ? 'on' : '', '" href="', self::e($base), '/admin/redeems?status=pending">Pending</a>',
            '<a class="', $status === 'approved' ? 'on' : '', '" href="', self::e($base), '/admin/redeems?status=approved">Approved</a>',
            '<a class="', $status === 'rejected' ? 'on' : '', '" href="', self::e($base), '/admin/redeems?status=rejected">Rejected</a>',
            '<a class="', $status === 'cancelled' ? 'on' : '', '" href="', self::e($base), '/admin/redeems?status=cancelled">Cancelled</a>',
            '<a class="', $status === 'all' ? 'on' : '', '" href="', self::e($base), '/admin/redeems?status=all">All</a>',
            '</div>',
            '<section class="section"><h2>Settings</h2><div class="card"><form method="post" action="', self::e($base), '/admin/redeem/save">', self::csrfField($csrf),
            '<label class="check"><input type="checkbox" name="enabled" value="1"', $c['enabled'] ? ' checked' : '', '> Allow redeem in the app</label>',
            '<div class="grid">',
            '<label>Min Pico coin<input type="number" name="minCoins" value="', self::e($c['minCoins']), '"></label>',
            '<label>Max Pico coin<input type="number" name="maxCoins" value="', self::e($c['maxCoins']), '"></label>',
            '<label>Max pending / player<input type="number" name="maxPendingPerUser" value="', self::e($c['maxPendingPerUser']), '"></label>',
            '<label>Coin per 1 BDT<input type="number" name="coinPerBdt" value="', self::e($c['coinPerBdt']), '"></label>',
            '</div><button>Save redeem settings</button></form></div></section>',
            '<section class="section"><h2>Requests</h2>', self::tableScrollOpen(),
            '<table class="one"><tr><th>ID<th>Player<th>Phone<th>Pico coin<th>BDT<th>Wallet<th>Number<th>Status<th>Time<th>Balance<th>Action</tr>';
        foreach ($rows as $r) {
            $prov = Redeem::PROVIDERS[(string) $r['wallet_provider']] ?? $r['wallet_provider'];
            $phone = isset($r['phone']) && $r['phone'] !== null && $r['phone'] !== '' ? Phone::display((string) $r['phone']) : '—';
            $pill = match ($r['status']) {
                'pending' => '<span class="pill">pending</span>',
                'approved' => '<span class="pill good">approved</span>',
                'cancelled' => '<span class="pill">cancelled</span>',
                default => '<span class="pill bad">rejected</span>',
            };
            echo '<tr><td>', self::e($r['id']),
                '<td><a href="', self::e($base), '/admin/player?id=', self::e($r['user_id']), '">', self::e($r['display_name']), '</a>',
                '<td>', self::e($phone),
                '<td>', self::e($r['coins']), '<td>', self::e($r['bdt_amount']),
                '<td>', self::e($prov),
                '<td><code>', self::e($r['wallet_number']), '</code>',
                '<td>', $pill,
                '<td>', self::e($r['created_at']),
                '<td>', self::e($r['balance_now']),
                $r['admin_note'] !== null && $r['admin_note'] !== '' ? ' · ' . self::e($r['admin_note']) : '',
                '<td class="actions">';
            if ($r['status'] === 'pending') {
                echo '<form class="inline" method="post" action="', self::e($base), '/admin/redeem/approve">', self::csrfField($csrf),
                    '<input type="hidden" name="id" value="', self::e($r['id']), '">',
                    '<input name="note" placeholder="Note" maxlength="255">',
                    '<button class="ok">Approve</button></form>',
                    '<form class="inline" method="post" action="', self::e($base), '/admin/redeem/reject">', self::csrfField($csrf),
                    '<input type="hidden" name="id" value="', self::e($r['id']), '">',
                    '<input name="note" placeholder="Reason" maxlength="255" required>',
                    '<button class="danger">Reject</button></form>';
            } else {
                echo '—';
            }
            echo '</tr>';
        }
        if ($rows === []) {
            echo '<tr><td colspan="11" class="muted">No requests in this list.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), '</section>';
        self::end();
    }

    private static function alertsPage(string $csrf): never
    {
        $base = self::base();
        $rows = AdminAlert::listRecent(100);
        self::begin('Security signals', 'alerts');
        self::pageLead('Automatic alerts: illegal redeem attempts, bad transfer targets, suspicious game actions.');
        echo '<p><form method="post" action="', self::e($base), '/admin/alerts/read">', self::csrfField($csrf),
            '<button class="ghost">Mark all read</button></form></p>',
            '<section class="section">', self::tableScrollOpen(),
            '<table class="one"><tr><th>When<th>Kind<th>Title<th>Detail<th>Player</tr>';
        foreach ($rows as $a) {
            $when = date('Y-m-d H:i', (int) ($a['createdAt'] / 1000));
            $player = $a['userId'] !== null
                ? '<a href="' . self::e($base) . '/admin/player?id=' . self::e($a['userId']) . '">' . self::e((string) ($a['playerName'] ?? ('#' . $a['userId']))) . '</a>'
                : '—';
            $unread = ($a['read'] ?? true) ? '' : ' class="row-alert"';
            echo '<tr', $unread, '><td>', self::e($when),
                '<td><code>', self::e($a['kind']), '</code>',
                '<td>', self::e($a['title']),
                '<td>', self::e((string) ($a['detail'] ?? '')),
                '<td>', $player, '</tr>';
        }
        if ($rows === []) {
            echo '<tr><td colspan="5" class="muted">No alerts yet.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), '</section>';
        self::end();
    }

    private static function transferPage(string $csrf): never
    {
        $base = self::base();
        $c = CoinTransfer::config();
        self::begin('Coin transfer', 'transfer');
        self::pageLead('Players send Pico coin by 6-digit game ID. Fee is taken from the sender on top of the amount.');
        echo '<section class="section"><div class="card"><form method="post" action="', self::e($base), '/admin/transfer/save">', self::csrfField($csrf),
            '<label class="check"><input type="checkbox" name="enabled" value="1"', $c['enabled'] ? ' checked' : '', '> Allow transfers in the app</label>',
            '<div class="grid">',
            '<label>Fee % (0–50)<input type="number" name="feePercent" min="0" max="50" value="', self::e($c['feePercent']), '"></label>',
            '<label>Min coins<input type="number" name="minCoins" min="1" value="', self::e($c['minCoins']), '"></label>',
            '<label>Max coins<input type="number" name="maxCoins" min="1" value="', self::e($c['maxCoins']), '"></label>',
            '</div><button>Save transfer settings</button></form></div></section>';
        self::end();
    }

    private static function saveTransferConfig(): never
    {
        CoinTransfer::save([
            'enabled' => isset($_POST['enabled']),
            'feePercent' => (int) ($_POST['feePercent'] ?? 10),
            'minCoins' => (int) ($_POST['minCoins'] ?? 10),
            'maxCoins' => (int) ($_POST['maxCoins'] ?? 500000),
        ]);
        self::back('/admin/transfer', 'Transfer settings saved.');
    }

    private static function saveDepositConfig(): never
    {
        CoinDeposit::save([
            'enabled' => ($_POST['enabled'] ?? '0') === '1',
            'minBdt' => (int) ($_POST['minBdt'] ?? 100),
            'maxBdt' => (int) ($_POST['maxBdt'] ?? 50000),
            'coinPerBdt' => (int) ($_POST['coinPerBdt'] ?? 1),
            'maxPendingPerUser' => (int) ($_POST['maxPendingPerUser'] ?? 3),
            'bkashNumber' => trim((string) ($_POST['bkashNumber'] ?? '')),
            'nagadNumber' => trim((string) ($_POST['nagadNumber'] ?? '')),
            'rocketNumber' => trim((string) ($_POST['rocketNumber'] ?? '')),
            'paymentType' => (string) ($_POST['paymentType'] ?? 'personal'),
        ]);
        self::back('/admin/deposits', 'Coin add settings saved.');
    }

    private static function saveZiniPayConfig(): never
    {
        $prev = ZiniPay::config();
        $key = trim((string) ($_POST['apiKey'] ?? ''));
        if (($_POST['clearKey'] ?? '0') === '1') {
            $key = '';
        } elseif ($key === '') {
            $key = (string) $prev['apiKey'];
        }
        $enabled = ($_POST['enabled'] ?? '0') === '1';
        if ($enabled && $key === '') {
            self::fail('API key is required when ZiniPay is enabled.', '/admin/zinipay');
        }
        ZiniPay::save([
            'enabled' => $enabled,
            'apiKey' => $key,
        ]);
        self::back('/admin/zinipay', 'ZiniPay settings saved.');
    }

    private static function ziniPayConfigBlock(string $csrf, string $base, bool $withUrls = true): void
    {
        if (!is_file(__DIR__ . '/ZiniPay.php')) {
            echo '<section class="section"><h2>ZiniPay</h2><p class="pill bad">Upload <code>src/ZiniPay.php</code> to the server to enable this section.</p></section>';
            return;
        }
        $z = ZiniPay::config();
        $urls = ZiniPay::adminUrls();
        $dep = CoinDeposit::config();
        $ready = ZiniPay::publicEnabled();
        echo '<section class="section"><h2>ZiniPay — auto coin add (WebView)</h2>',
            '<p class="hint">Status in app: <strong>', $ready ? 'AUTO enabled' : 'AUTO off (enable below + API key)', '</strong>',
            ' · Key: ', self::e(ZiniPay::maskedApiKey()), '</p>',
            '<div class="card"><form method="post" action="', self::e($base), '/admin/zinipay/save">', self::csrfField($csrf),
            '<label class="check"><input type="checkbox" name="enabled" value="1"', $z['enabled'] ? ' checked' : '', '> Enable ZiniPay in the app (ADD → AUTO)</label>',
            '<p class="hint">Amount limits: ', self::e($dep['minBdt']), '–', self::e($dep['maxBdt']), ' BDT · ',
            self::e($dep['coinPerBdt']), ' Pico coin per 1 BDT (same as manual coin add above).</p>',
            '<label>Brand API key<input type="password" name="apiKey" value="" autocomplete="new-password" placeholder="Paste sandbox or live key"></label>',
            '<p class="hint">ZiniPay dashboard → Menu → Brands → Brand key. Leave blank to keep current key.</p>',
            '<label class="check"><input type="checkbox" name="clearKey" value="1"> Clear stored API key</label>',
            '<button>Save ZiniPay</button></form></div>';
        if ($withUrls) {
            $appUrl = $urls['appUrl'];
            echo '<div class="card grid" style="margin-top:12px"><p class="hint"><strong>APP_URL:</strong> ',
                $appUrl !== '' ? self::e($appUrl) : '<span class="pill bad">Set APP_URL in server .env</span>',
                '</p>';
            foreach ([
                'Webhook (paste in ZiniPay)' => $urls['webhookUrl'],
                'Redirect example' => $urls['returnUrlExample'],
            ] as $label => $url) {
                echo '<label>', self::e($label), '<input readonly value="', self::e($url), '" onclick="this.select()"></label>';
            }
            echo '</div>';
        }
        echo '</section>';
    }

    private static function ziniPayPage(string $csrf): never
    {
        $base = self::base();
        $urls = ZiniPay::adminUrls();
        $appUrl = $urls['appUrl'];
        $ready = ZiniPay::publicEnabled();
        $rows = [];
        try {
            $rows = ZiniPay::listRecent(80);
        } catch (\Throwable $e) {
            error_log('[admin/zinipay] ' . $e->getMessage());
        }
        self::begin('ZiniPay (auto coin add)', 'zinipay');
        self::pageLead('Players choose <b>AUTO</b> on the ADD tab — the app opens ZiniPay in WebView. API key never goes in the APK.');
        echo '<section class="section"><h2>Status</h2><div class="stats">';
        echo '<div class="stat"><b>', $ready ? 'ON' : 'OFF', '</b><span>Auto add in app</span></div>';
        echo '<div class="stat"><b>', self::e(ZiniPay::maskedApiKey()), '</b><span>API key (masked)</span></div>';
        echo '<div class="stat"><b>', $appUrl !== '' ? 'OK' : 'MISSING', '</b><span>APP_URL in .env</span></div>';
        echo '</div>';
        if ($appUrl === '') {
            echo '<p class="muted">Set <code>APP_URL=https://your-domain.com</code> in server .env — required for redirect and webhook.</p>';
        }
        echo '</section>';

        self::ziniPayConfigBlock($csrf, $base, true);

        echo '<section class="section"><h2>API reference</h2><div class="card grid">';
        foreach ([
            'Create invoice' => $urls['apiCreate'],
            'Verify invoice' => $urls['apiVerify'],
        ] as $label => $url) {
            echo '<label>', self::e($label), '<input readonly value="', self::e($url), '" onclick="this.select()"></label>';
        }
        echo '</div></section>';

        echo '<section class="section"><h2>Recent auto payments</h2>', self::tableScrollOpen(),
            '<table class="one"><tr><th>ID<th>Player<th>Phone<th>BDT<th>Pico coin<th>Invoice<th>Status<th>Credited<th>Time</tr>';
        foreach ($rows as $r) {
            $phone = isset($r['phone']) && $r['phone'] !== null && $r['phone'] !== '' ? Phone::display((string) $r['phone']) : '—';
            $pill = ($r['credited'] ?? false)
                ? '<span class="pill good">credited</span>'
                : '<span class="pill">' . self::e((string) $r['status']) . '</span>';
            echo '<tr><td>', self::e($r['id']),
                '<td><a href="', self::e($base), '/admin/player?id=', self::e($r['userId']), '">', self::e($r['playerName']), '</a>',
                '<td>', self::e($phone),
                '<td>', self::e($r['bdt']),
                '<td>', self::e($r['coins']),
                '<td><code>', self::e((string) ($r['invoiceId'] ?? '—')), '</code>',
                '<td>', $pill,
                '<td>', ($r['credited'] ?? false) ? 'yes' : 'no',
                '<td>', self::e((string) $r['createdAt']),
                '</tr>';
        }
        if ($rows === []) {
            echo '<tr><td colspan="9" class="muted">No ZiniPay payments yet.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), '</section>';
        self::end();
    }

    private static function reviewDeposit(bool $approve): never
    {
        $id = (int) ($_POST['id'] ?? 0);
        $note = trim((string) ($_POST['note'] ?? ''));
        $back = '/admin/deposits';
        try {
            if ($approve) {
                CoinDeposit::approve($id, $note);
            } else {
                if ($note === '') {
                    self::fail('Add a reason when rejecting (shown to the player).', $back);
                }
                CoinDeposit::reject($id, $note);
            }
        } catch (ApiError $e) {
            self::fail($e->getMessage(), $back);
        }
        self::back($back, $approve ? 'Deposit approved and coins credited.' : 'Deposit rejected.');
    }

    private static function depositsPage(string $csrf): never
    {
        $base = self::base();
        $status = (string) ($_GET['status'] ?? 'pending');
        if (!in_array($status, ['pending', 'approved', 'rejected', 'all'], true)) {
            $status = 'pending';
        }
        $where = $status === 'all' ? '1=1' : 'd.status = ' . ($status === 'pending' ? "'pending'" : ($status === 'approved' ? "'approved'" : "'rejected'"));
        $rows = Db::all(
            "SELECT d.*, u.display_name, u.phone, u.coins AS balance_now
             FROM coin_deposit_requests d JOIN users u ON u.id = d.user_id
             WHERE $where ORDER BY d.id DESC LIMIT 100"
        );
        $c = CoinDeposit::config();
        self::begin('Manual coin add (bKash / Nagad)', 'deposits');
        self::pageLead('Players pay your numbers and submit TrxID. Approve adds Pico coin; reject does not.');
        echo '<div class="filters">',
            '<a class="', $status === 'pending' ? 'on' : '', '" href="', self::e($base), '/admin/deposits?status=pending">Pending</a>',
            '<a class="', $status === 'approved' ? 'on' : '', '" href="', self::e($base), '/admin/deposits?status=approved">Approved</a>',
            '<a class="', $status === 'rejected' ? 'on' : '', '" href="', self::e($base), '/admin/deposits?status=rejected">Rejected</a>',
            '<a class="', $status === 'all' ? 'on' : '', '" href="', self::e($base), '/admin/deposits?status=all">All</a>',
            '</div>',
            '<section class="section"><h2>Payment numbers</h2><p class="hint">Shown in the app — players can copy.</p>',
            '<div class="card"><form method="post" action="', self::e($base), '/admin/deposit/save">', self::csrfField($csrf),
            '<label class="check"><input type="checkbox" name="enabled" value="1"', $c['enabled'] ? ' checked' : '', '> Allow manual coin add in the app</label>',
            '<div class="grid">',
            '<label>bKash number<input name="bkashNumber" value="', self::e($c['bkashNumber']), '" placeholder="01XXXXXXXXX"></label>',
            '<label>Nagad number<input name="nagadNumber" value="', self::e($c['nagadNumber']), '" placeholder="01XXXXXXXXX"></label>',
            '<label>Rocket number (optional)<input name="rocketNumber" value="', self::e($c['rocketNumber']), '"></label>',
            '<label>Min BDT<input type="number" name="minBdt" value="', self::e($c['minBdt']), '"></label>',
            '<label>Max BDT<input type="number" name="maxBdt" value="', self::e($c['maxBdt']), '"></label>',
            '<label>Coin per 1 BDT<input type="number" name="coinPerBdt" value="', self::e($c['coinPerBdt']), '"></label>',
            '<label>Max pending / player<input type="number" name="maxPendingPerUser" value="', self::e($c['maxPendingPerUser']), '"></label>',
            '<label>Account type<select name="paymentType">',
            '<option value="personal"', $c['paymentType'] === 'personal' ? ' selected' : '', '>Personal</option>',
            '<option value="agent"', $c['paymentType'] === 'agent' ? ' selected' : '', '>Agent</option>',
            '<option value="merchant"', $c['paymentType'] === 'merchant' ? ' selected' : '', '>Merchant</option>',
            '</select></label>',
            '</div><button>Save payment settings</button></form></div></section>';
        self::ziniPayConfigBlock($csrf, $base, true);
        echo '<section class="section"><h2>Deposit requests</h2>', self::tableScrollOpen(),
            '<table class="one"><tr><th>ID<th>Player<th>Phone<th>Method<th>From #<th>BDT<th>Pico coin<th>TrxID<th>Status<th>Time<th>Balance<th>Action</tr>';
        foreach ($rows as $r) {
            $prov = CoinDeposit::PROVIDERS[(string) $r['provider']] ?? $r['provider'];
            $phone = isset($r['phone']) && $r['phone'] !== null && $r['phone'] !== '' ? Phone::display((string) $r['phone']) : '—';
            $pill = match ($r['status']) {
                'pending' => '<span class="pill">pending</span>',
                'approved' => '<span class="pill good">approved</span>',
                default => '<span class="pill bad">rejected</span>',
            };
            echo '<tr><td>', self::e($r['id']),
                '<td><a href="', self::e($base), '/admin/player?id=', self::e($r['user_id']), '">', self::e($r['display_name']), '</a>',
                '<td>', self::e($phone),
                '<td>', self::e($prov),
                '<td><code>', self::e($r['payer_number']), '</code>',
                '<td>', self::e($r['bdt_amount']),
                '<td>', self::e($r['coins']),
                '<td><code>', self::e($r['trx_id']), '</code>',
                '<td>', $pill,
                '<td>', self::e($r['created_at']),
                '<td>', self::e($r['balance_now']),
                $r['admin_note'] !== null && $r['admin_note'] !== '' ? ' · ' . self::e($r['admin_note']) : '',
                '<td class="actions">';
            if ($r['status'] === 'pending') {
                echo '<form class="inline" method="post" action="', self::e($base), '/admin/deposit/approve">', self::csrfField($csrf),
                    '<input type="hidden" name="id" value="', self::e($r['id']), '">',
                    '<input name="note" placeholder="Note" maxlength="255">',
                    '<button class="ok">Approve</button></form>',
                    '<form class="inline" method="post" action="', self::e($base), '/admin/deposit/reject">', self::csrfField($csrf),
                    '<input type="hidden" name="id" value="', self::e($r['id']), '">',
                    '<input name="note" placeholder="Reason" maxlength="255" required>',
                    '<button class="danger">Reject</button></form>';
            } else {
                echo '—';
            }
            echo '</tr>';
        }
        if ($rows === []) {
            echo '<tr><td colspan="12" class="muted">No requests in this list.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), '</section>';
        self::end();
    }

    private static function coinShopPage(string $csrf): never
    {
        $base = self::base();
        $c = CoinShop::config();
        $global = (int) $c['globalDiscountPercent'];
        self::begin('Coin shop', 'coin-shop');
        self::pageLead(
            'Shop packs. <b>Base coins</b> = BDT amount on the add-coin page. '
            . '<b>Bonus %</b> = extra Pico coins on top (100 at 5% → player gets 105). '
            . 'Global % adds to every pack. Re-save a pack with the same ID to update it.'
        );
        echo '<section class="section"><div class="card"><form class="row" method="post" action="', self::e($base), '/admin/coin-shop/global">', self::csrfField($csrf),
            '<label>Global discount on coins (%)<input type="number" name="globalDiscountPercent" min="0" max="100" required value="', self::e($global), '"></label>',
            '<button>Save global discount</button></form></div></section>',
            '<section class="section"><h2>Packs</h2>', self::tableScrollOpen(),
            '<table><tr><th>Active<th>ID<th>Name<th>Base coins<th>Bonus %<th>Global %<th>Player gets<th>Price (coins)<th>Sort<th></tr>';
        $packs = $c['packs'];
        usort($packs, static fn (array $a, array $b): int => ($a['sort'] <=> $b['sort']) ?: strcmp($a['id'], $b['id']));
        foreach ($packs as $p) {
            $gets = CoinShop::receiveCoins($p, $global);
            echo '<tr><td>', ($p['active'] ?? true) ? '<span class="pill good">yes</span>' : '<span class="pill">no</span>',
                '<td>', self::e($p['id']), '<td>', self::e($p['name']),
                '<td>', self::e($p['coins']), '<td>', self::e($p['discountPercent']), '%',
                '<td>', self::e($global), '%<td><b>', self::e($gets), '</b>',
                '<td>', self::e($p['priceCoins']),
                '<td>', self::e($p['sort']), '<td>';
            echo '<form method="post" action="', self::e($base), '/admin/coin-shop/delete" style="display:inline">', self::csrfField($csrf),
                '<input type="hidden" name="id" value="', self::e($p['id']), '"><button type="submit">Delete</button></form></tr>';
        }
        echo '</table>', self::tableScrollClose(), '</section>',
            '<section class="section"><h2>Add or update pack</h2><div class="card"><form method="post" action="', self::e($base), '/admin/coin-shop/pack">', self::csrfField($csrf),
            '<div class="grid">',
            '<label>Pack id (letters, numbers, _)<input name="id" maxlength="32" required pattern="[a-zA-Z0-9_-]+" placeholder="starter"></label>',
            '<label>Name<input name="name" maxlength="32" required placeholder="STARTER"></label>',
            '<label>Base coins<input type="number" name="coins" min="1" max="100000000" required></label>',
            '<label>Bonus on deposit (%)<input type="number" name="discountPercent" min="0" max="100" value="5" title="Extra coins on top of base amount"></label>',
            '<label>Price in coins (0 = free once)<input type="number" name="priceCoins" min="0" max="100000000" value="0"></label>',
            '<label>Sort order<input type="number" name="sort" value="0"></label>',
            '<label>Active<select name="active"><option value="1">yes</option><option value="0">no</option></select></label>',
            '</div><p></p><button>Save pack</button></form></div></section>';
        self::end();
    }

    private static function economyPage(string $csrf): never
    {
        $base = self::base();
        $c = Economy::config();
        self::begin('Economy', 'economy');
        self::pageLead(
            'House fee, stakes, jackpot, daily bonus and starting coins. Referral % on '
            . '<a href="' . self::e($base) . '/admin/referrals">Referrals</a>. New matches use settings after save.'
        );
        echo '<form method="post" action="', self::e($base), '/admin/economy">', self::csrfField($csrf),
            '<div class="card"><h2 style="margin:0 0 12px">General</h2><div class="grid">',
            '<label>House fee (% of stake)<input type="number" name="rakePercent" min="0" max="50" required value="', self::e($c['rakePercent']), '"></label>',
            '<label>Win payout % <span class="muted">(1v1: stake 100 → win ', self::e(Economy::winnerPrize(100, 2)), ' at current setting)</span>',
            '<input type="number" name="winPayoutPercent" min="50" max="300" required value="', self::e($c['winPayoutPercent'] ?? 200), '"></label>',
            '<label>Joining balance (new accounts)<input type="number" name="startCoins" min="0" max="100000000" required value="', self::e($c['startCoins']), '"></label>',
            '</div>',
            '<p class="hint"><b>Win payout</b> controls how much the winner gets in Pool / Ludo / Carrom. ',
            '200 = full pot (100 stake → 200 win). 180 = 100 stake → 180 win. House keeps the rest + the entry fee. ',
            'Billiard poker still uses the jackpot table below.</p></div>';
        $names = array_values(array_slice($c['stakeNames'] ?? Economy::DEFAULTS['stakeNames'], 0, 8));
        while (count($names) < 8) {
            $names[] = Economy::DEFAULTS['stakeNames'][count($names)] ?? 'LEVEL';
        }
        echo '<div class="card"><h2 style="margin:0 0 12px">Table names (8 levels)</h2>',
            '<p class="hint">Shown in the app instead of “buy in”. Left = lowest stake.</p><div class="row">';
        foreach ($names as $i => $name) {
            echo '<label>ID ', self::e($i + 1), '<input type="text" name="stakeNames[]" maxlength="16" required value="', self::e($name), '"></label>';
        }
        echo '</div></div>';
        $billiard = array_values(array_slice($c['billiardStakes'], 0, 8));
        while (count($billiard) < 8) {
            $billiard[] = Economy::DEFAULTS['billiardStakes'][count($billiard)] ?? 100;
        }
        echo '<div class="card"><h2 style="margin:0 0 12px">Pool / Ludo / Carrom stakes</h2>',
            '<p class="hint">Entry = stake + house fee. Exactly 8 levels.</p><div class="row">';
        foreach ($billiard as $i => $stake) {
            echo '<label>', self::e($names[$i] ?? ('Level ' . ($i + 1))), ' stake<input type="number" name="billiardStakes[]" min="1" max="100000000" required value="', self::e($stake), '"></label>';
        }
        echo '</div></div>';
        $poker = array_values(array_slice($c['pokerStakes'], 0, 8));
        while (count($poker) < 8) {
            $poker[] = Economy::DEFAULTS['pokerStakes'][count($poker)] ?? 100;
        }
        echo '<div class="card"><h2 style="margin:0 0 12px">Billiard poker stakes</h2><div class="row">';
        foreach ($poker as $i => $stake) {
            echo '<label>', self::e($names[$i] ?? ('Level ' . ($i + 1))), ' stake<input type="number" name="pokerStakes[]" min="1" max="100000000" required value="', self::e($stake), '"></label>';
        }
        echo '</div></div>',
            '<div class="card"><h2 style="margin:0 0 12px">Daily login bonus (7 days)</h2><p class="hint">Day 1 = first claim, then day 2, … resets after day 7.</p>',
            '<div class="grid">';
        foreach ($c['dailyBonus'] as $i => $coins) {
            $gems = $c['dailyGems'][$i] ?? 0;
            echo '<label>Day ', self::e($i + 1), ' coins<input type="number" name="dailyBonus[]" min="1" max="100000000" required value="', self::e($coins), '"></label>',
                '<label>Day ', self::e($i + 1), ' gems<input type="number" name="dailyGems[]" min="0" max="100000000" required value="', self::e($gems), '"></label>';
        }
        echo '</div></div>',
            '<div class="card"><h2 style="margin:0 0 12px">Poker jackpot multipliers</h2>',
            '<p class="hint">Prize = stake × multiplier. Weight = how often (higher = more common). All weights together define the draw.</p>',
            self::tableScrollOpen(),
            '<table><tr><th>Multiplier (×)<th>Weight</tr>';
        foreach ($c['jackpot'] as $j) {
            echo '<tr><td><input type="number" name="jackpot_x[]" min="1" max="1000000" required value="', self::e($j['x']), '" style="width:120px">',
                '<td><input type="number" name="jackpot_weight[]" min="1" max="2000000000" required value="', self::e($j['weight']), '" style="width:160px"></tr>';
        }
        echo '<tr><td><input type="number" name="jackpot_x[]" min="0" max="1000000" placeholder="×" style="width:120px">',
            '<td><input type="number" name="jackpot_weight[]" min="0" max="2000000000" placeholder="Weight" style="width:160px"></tr>',
            '</table>', self::tableScrollClose(),
            '<p class="hint">Use the blank row to add a multiplier. Clear both cells in a row to remove it on save.</p></div>',
            '<button type="submit">Save economy</button></form>';
        self::end();
    }

    private static function savePushConfig(): never
    {
        Push::save([
            'enabled' => ($_POST['enabled'] ?? '0') === '1',
            'depositApproved' => ($_POST['depositApproved'] ?? '0') === '1',
            'depositRejected' => ($_POST['depositRejected'] ?? '0') === '1',
            'redeemApproved' => ($_POST['redeemApproved'] ?? '0') === '1',
            'redeemRejected' => ($_POST['redeemRejected'] ?? '0') === '1',
            'challenge' => ($_POST['challenge'] ?? '0') === '1',
            'adminBroadcast' => ($_POST['adminBroadcast'] ?? '0') === '1',
            'channelId' => trim((string) ($_POST['channelId'] ?? '')),
            'channelName' => trim((string) ($_POST['channelName'] ?? '')),
        ]);
        self::back('/admin/push', 'Push notification settings saved.');
    }

    private static function pushBroadcast(): never
    {
        $title = trim((string) ($_POST['title'] ?? ''));
        $body = trim((string) ($_POST['body'] ?? ''));
        if ($title === '' || $body === '') {
            self::fail('Title and body are required.', '/admin/push');
        }
        $r = Push::broadcast($title, $body);
        self::back(
            '/admin/push',
            'Broadcast sent. Inbox: ' . $r['inbox'] . ' players. FCM ok: ' . $r['sent'] . ', failed: ' . $r['failed'] . '.'
        );
    }

    private static function pushTest(): never
    {
        $uid = (int) ($_POST['userId'] ?? 0);
        $title = trim((string) ($_POST['title'] ?? 'PikoPe test'));
        $body = trim((string) ($_POST['body'] ?? 'Push is working.'));
        if ($uid <= 0) {
            self::fail('Enter a valid player ID.', '/admin/push');
        }
        $r = Push::sendTest($uid, $title, $body);
        self::back(
            '/admin/push',
            'Test push to player #' . $uid . ': FCM ok ' . $r['sent'] . ', failed ' . $r['failed'] . '. Inbox updated.'
        );
    }

    private static function pushPage(string $csrf): never
    {
        $base = self::base();
        $c = Push::config();
        $st = Push::adminStats();
        self::begin('Push notifications (APK)', 'push');
        self::pageLead('Firebase Cloud Messaging for Android APK. Set FCM_SERVER_KEY in .env (Firebase console → Project settings → Cloud Messaging → Server key).');
        echo '<section class="section"><div class="stats">',
            '<div class="stat"><b>', $st['enabled'] ? 'ON' : 'OFF', '</b><span>push master</span></div>',
            '<div class="stat"><b>', $st['fcm'] ? 'Yes' : 'No', '</b><span>FCM key in .env</span></div>',
            '<div class="stat"><b>', self::e($st['tokens']), '</b><span>device tokens</span></div>',
            '<div class="stat"><b>', self::e($st['devices']), '</b><span>players with a token</span></div>',
            '</div></section>',
            '<section class="section"><h2>Automatic events</h2><div class="card"><form method="post" action="', self::e($base), '/admin/push/save">', self::csrfField($csrf),
            '<label class="check"><input type="checkbox" name="enabled" value="1"', $c['enabled'] ? ' checked' : '', '> Enable push (master switch)</label>',
            '<div class="grid">',
            '<label class="check"><input type="checkbox" name="depositApproved" value="1"', $c['depositApproved'] ? ' checked' : '', '> Coin add approved</label>',
            '<label class="check"><input type="checkbox" name="depositRejected" value="1"', $c['depositRejected'] ? ' checked' : '', '> Coin add rejected</label>',
            '<label class="check"><input type="checkbox" name="redeemApproved" value="1"', $c['redeemApproved'] ? ' checked' : '', '> Redeem approved</label>',
            '<label class="check"><input type="checkbox" name="redeemRejected" value="1"', $c['redeemRejected'] ? ' checked' : '', '> Redeem rejected</label>',
            '<label class="check"><input type="checkbox" name="challenge" value="1"', $c['challenge'] ? ' checked' : '', '> 1v1 challenge received</label>',
            '<label class="check"><input type="checkbox" name="adminBroadcast" value="1"', $c['adminBroadcast'] ? ' checked' : '', '> Admin broadcast / notice push</label>',
            '<label>Android channel id<input name="channelId" maxlength="40" value="', self::e($c['channelId']), '"></label>',
            '<label>Android channel name<input name="channelName" maxlength="40" value="', self::e($c['channelName']), '"></label>',
            '</div><p class="hint">Players also see messages in the in-app notification list when the app is open.</p>',
            '<button>Save push settings</button></form></div></section>',
            '<section class="section"><h2>Broadcast to all</h2><div class="card"><form method="post" action="', self::e($base), '/admin/push/broadcast">', self::csrfField($csrf),
            '<div class="grid"><label class="span2">Title<input name="title" maxlength="80" required></label>',
            '<label class="span2">Message<textarea name="body" rows="3" maxlength="500" required></textarea></label></div>',
            '<button>Send to everyone</button></form></div></section>',
            '<section class="section"><h2>Test one player</h2><div class="card"><form class="row" method="post" action="', self::e($base), '/admin/push/test">', self::csrfField($csrf),
            '<label>Player ID<input type="number" name="userId" min="1" required placeholder="User id from Players"></label>',
            '<label>Title<input name="title" maxlength="80" value="PikoPe test"></label>',
            '<label>Body<input name="body" maxlength="500" value="Push notification is working."></label>',
            '<button>Send test</button></form></div></section>';
        self::end();
    }

    private static function savePromotions(): never
    {
        Promotions::save([
            'depositBonusEnabled' => ($_POST['depositBonusEnabled'] ?? '0') === '1',
            'depositBonusPercent' => (int) ($_POST['depositBonusPercent'] ?? 0),
            'depositEndsAt' => trim((string) ($_POST['depositEndsAt'] ?? '')),
            'winBonusEnabled' => ($_POST['winBonusEnabled'] ?? '0') === '1',
            'winBonusPercent' => (int) ($_POST['winBonusPercent'] ?? 0),
            'winEndsAt' => trim((string) ($_POST['winEndsAt'] ?? '')),
            'title' => trim((string) ($_POST['title'] ?? '')),
        ]);
        self::back('/admin/promotions', 'Promotion settings saved.');
    }

    private static function promotionsPage(string $csrf): never
    {
        $base = self::base();
        $c = Promotions::config();
        $depOn = Promotions::depositBonusActive();
        $winOn = Promotions::winBonusActive();
        self::begin('Promotions', 'promotions');
        self::pageLead(
            'Optional time-limited bonuses. Default is OFF. Bonus applies once per deposit request (at submit) and once per match win — never stacked twice.'
        );
        echo '<div class="alert ok">Security: same TrxID cannot be used twice; admin approve cannot credit the same request twice; match prize pays only when the game first finishes.</div>',
            '<section class="section"><div class="stats">',
            '<div class="stat"><b>', $depOn ? 'ON' : 'OFF', '</b><span>deposit bonus now</span></div>',
            '<div class="stat"><b>', $winOn ? 'ON' : 'OFF', '</b><span>win bonus now</span></div>',
            '<div class="stat"><b>', self::e((int) $c['depositBonusPercent']), '%</b><span>extra on manual add</span></div>',
            '<div class="stat"><b>', self::e((int) $c['winBonusPercent']), '%</b><span>extra on match prize</span></div>',
            '</div></section>',
            '<section class="section"><div class="card"><form method="post" action="', self::e($base), '/admin/promotions">', self::csrfField($csrf),
            '<label>Promo title (app)<input name="title" maxlength="80" value="', self::e($c['title']), '"></label>',
            '<h2 class="card-title">Manual coin add bonus</h2>',
            '<label class="check"><input type="checkbox" name="depositBonusEnabled" value="1"', $c['depositBonusEnabled'] ? ' checked' : '', '> Enable deposit bonus</label>',
            '<div class="grid">',
            '<label>Extra coins (% of base)<span class="muted">100 = double total coins on approve</span>',
            '<input type="number" name="depositBonusPercent" min="0" max="500" value="', self::e($c['depositBonusPercent']), '"></label>',
            '<label>Ends (optional)<input type="datetime-local" name="depositEndsAt" value="',
            $c['depositEndsAt'] !== '' ? self::e(str_replace(' ', 'T', substr((string) $c['depositEndsAt'], 0, 16))) : '',
            '"></label></div>',
            '<h2 class="card-title">Match win bonus</h2>',
            '<label class="check"><input type="checkbox" name="winBonusEnabled" value="1"', $c['winBonusEnabled'] ? ' checked' : '', '> Enable win bonus</label>',
            '<div class="grid">',
            '<label>Extra prize (% of room prize)<span class="muted">100 = double the winner payout</span>',
            '<input type="number" name="winBonusPercent" min="0" max="500" value="', self::e($c['winBonusPercent']), '"></label>',
            '<label>Ends (optional)<input type="datetime-local" name="winEndsAt" value="',
            $c['winEndsAt'] !== '' ? self::e(str_replace(' ', 'T', substr((string) $c['winEndsAt'], 0, 16))) : '',
            '"></label></div>',
            '<p class="hint">Does not stack with coin-shop discounts or referral commission. Turn both off when not running a campaign.</p>',
            '<button>Save promotions</button></form></div></section>';
        self::end();
    }

    private static function noticesPage(string $csrf): never
    {
        $base = self::base();
        $notices = Db::all('SELECT id, title, body, kind, active, created_at, expires_at FROM notices ORDER BY id DESC LIMIT 100');
        self::begin('Notices', 'notices');
        self::pageLead('"news" = in-app inbox. "banner" = also on the home screen.');
        echo '<section class="section"><div class="card"><form method="post" action="', self::e($base), '/admin/notice">', self::csrfField($csrf),
            '<div class="grid"><label class="span2">Title<input name="title" maxlength="80" required></label>',
            '<label class="span2">Body<textarea name="body" rows="4" maxlength="500" required></textarea></label>',
            '<label>Kind<select name="kind"><option value="news">news</option><option value="banner">banner</option></select></label>',
            '<label>Expires<input type="datetime-local" name="expires"></label>',
            '<label class="check"><input type="checkbox" name="push" value="1"> Also send APK push to all players</label>',
            '</div><p></p><button>Post notice</button></form></div></section>',
            '<section class="section"><h2>Published</h2>', self::tableScrollOpen(),
            '<table><tr><th>ID<th>Kind<th>Title<th>Active<th>Created<th>Expires<th></tr>';
        foreach ($notices as $no) {
            echo '<tr><td>', self::e($no['id']), '<td>', self::e($no['kind']), '<td>', self::e($no['title']),
                '<td>', self::on($no['active']) ? '<span class="pill good">yes</span>' : '<span class="pill">no</span>',
                '<td>', self::e($no['created_at']), '<td>', self::e($no['expires_at'] ?? ''), '<td>';
            if (self::on($no['active'])) {
                echo '<form class="inline" method="post" action="', self::e($base), '/admin/notice/off">', self::csrfField($csrf),
                    '<input type="hidden" name="id" value="', self::e($no['id']), '"><button class="ghost">Deactivate</button></form>';
            }
            echo '</tr>';
        }
        if ($notices === []) {
            echo '<tr><td colspan="7" class="muted">No notices yet.</td></tr>';
        }
        echo '</table>', self::tableScrollClose(), '</section>';
        self::end();
    }

    private static function saveSupport(): never
    {
        try {
            SupportLinks::save([
                'facebook' => trim((string) ($_POST['facebook'] ?? '')),
                'telegram' => trim((string) ($_POST['telegram'] ?? '')),
            ]);
        } catch (ApiError $e) {
            self::back('/admin/support', null, $e->getMessage());
        }
        self::back('/admin/support', 'Support links saved.');
    }

    private static function supportPage(string $csrf): never
    {
        $base = self::base();
        $c = SupportLinks::config();
        self::begin('Support links', 'support');
        self::pageLead('These two buttons appear in the app Settings. Leave a box empty to hide that button. Paste a full link, such as https://facebook.com/yourpage or https://t.me/yourchannel.');
        echo '<section class="section"><div class="card"><form method="post" action="', self::e($base), '/admin/support">', self::csrfField($csrf),
            '<div class="grid">',
            '<label class="span2">Facebook link<input name="facebook" maxlength="300" value="', self::e($c['facebook']), '" placeholder="https://facebook.com/yourpage"></label>',
            '<label class="span2">Telegram link<input name="telegram" maxlength="300" value="', self::e($c['telegram']), '" placeholder="https://t.me/yourchannel"></label>',
            '</div><button>Save support links</button></form></div></section>';
        self::end();
    }

    private static function saveAppUpdate(): never
    {
        try {
            AppUpdate::save([
                'enabled' => ($_POST['enabled'] ?? '0') === '1',
                'versionCode' => (int) ($_POST['versionCode'] ?? 0),
                'versionName' => trim((string) ($_POST['versionName'] ?? '')),
                'apkUrl' => trim((string) ($_POST['apkUrl'] ?? '')),
                'apkSha256' => trim((string) ($_POST['apkSha256'] ?? '')),
                'notes' => trim((string) ($_POST['notes'] ?? '')),
                'required' => ($_POST['required'] ?? '0') === '1',
            ]);
        } catch (ApiError $e) {
            self::back('/admin/app-update', null, $e->getMessage());
        }
        self::back('/admin/app-update', 'App update saved.');
    }

    private static function appUpdatePage(string $csrf): never
    {
        $base = self::base();
        $c = AppUpdate::config();
        self::begin('App update', 'app-update');
        self::pageLead('The installed app checks this when it opens. If the version code is higher than the one on the phone, it downloads the APK inside the app and Android opens the install screen. Players still confirm that install. Host the file on HTTPS (File Manager is fine) and paste the link. The build that first added this updater is version code 2.');
        echo '<section class="section"><div class="card"><form method="post" action="', self::e($base), '/admin/app-update">', self::csrfField($csrf),
            '<div class="grid">',
            '<label class="check"><input type="checkbox" name="enabled" value="1"', $c['enabled'] ? ' checked' : '', '> Update is on</label>',
            '<label class="check"><input type="checkbox" name="required" value="1"', $c['required'] ? ' checked' : '', '> Players must install it</label>',
            '<label>Version code<input type="number" name="versionCode" min="1" max="999999" value="', self::e((int) $c['versionCode']), '" placeholder="3"></label>',
            '<label>Version name<input name="versionName" maxlength="40" value="', self::e($c['versionName']), '" placeholder="1.0.2"></label>',
            '<label class="span2">APK link<input name="apkUrl" maxlength="400" value="', self::e($c['apkUrl']), '" placeholder="https://pikope.bet369win.com/pikope.apk"></label>',
            '<label class="span2">APK SHA-256 (optional)<input name="apkSha256" maxlength="64" value="', self::e($c['apkSha256'] ?? ''), '" placeholder="64 hex chars; app rejects a mismatch"></label>',
            '<label class="span2">Note for players<textarea name="notes" rows="3" maxlength="400">', self::e($c['notes']), '</textarea></label>',
            '</div><button>Save app update</button></form></div></section>';
        self::end();
    }

    private static function saveAdminAccount(): never
    {
        try {
            AdminAuth::change(
                (string) ($_POST['current_password'] ?? ''),
                (string) ($_POST['new_username'] ?? AdminAuth::username()),
                (string) ($_POST['new_password'] ?? ''),
                (string) ($_POST['confirm_password'] ?? ''),
            );
        } catch (ApiError $e) {
            self::fail($e->getMessage(), '/admin/account');
        }
        self::back(
            '/admin/account',
            'Admin sign-in updated. Your browser may ask you to sign in again with the new username and password.'
        );
    }

    private static function accountPage(string $csrf): never
    {
        $base = self::base();
        $user = AdminAuth::username();
        $stored = AdminAuth::usesStoredCredentials();
        self::begin('Admin password', 'account');
        self::pageLead(
            'Change the username and password for this admin panel (HTTP Basic sign-in). '
            . 'Minimum 12 characters for the new password. After saving, use the new details when the browser prompts you.'
        );
        echo '<section class="section"><div class="card"><form method="post" action="', self::e($base), '/admin/account">', self::csrfField($csrf),
            '<p class="hint">Signed in as <b>', self::e($user), '</b>. ',
            $stored ? 'Credentials are stored in the database (overrides .env).' : 'Still using ADMIN_USER / ADMIN_PASS from .env until you save here.</p>',
            '<div class="grid">',
            '<label>Current password<input type="password" name="current_password" required autocomplete="current-password"></label>',
            '<label>New username<input name="new_username" maxlength="64" required pattern="[A-Za-z0-9._-]+" value="', self::e($user), '"></label>',
            '<label>New password<input type="password" name="new_password" required minlength="12" autocomplete="new-password"></label>',
            '<label>Confirm new password<input type="password" name="confirm_password" required minlength="12" autocomplete="new-password"></label>',
            '</div><p class="hint">Leave .env ADMIN_PASS as a backup recovery only; login uses the saved password once you change it here.</p>',
            '<button>Save admin sign-in</button></form></div></section>';
        self::end();
    }
}
