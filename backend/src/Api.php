<?php
declare(strict_types=1);

namespace App;

/** Routes and the account / profile / leaderboard handlers. */
final class Api
{
    private const AVATAR_TYPES = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];
    private const AVATAR_MAX_BYTES = 2 * 1024 * 1024;
    private const BOT_WIN_XP = 10;
    private const BOT_PLAY_XP = 4;

    public static function handle(): never
    {
        $origin = trim(Config::get('CORS_ORIGIN', ''));
        if ($origin !== '') {
            header("Access-Control-Allow-Origin: $origin");
            header('Access-Control-Allow-Headers: Authorization, Content-Type');
            header('Access-Control-Allow-Methods: GET, POST, PATCH, OPTIONS');
        }
        header('X-Content-Type-Options: nosniff');
        header('Referrer-Policy: no-referrer');
        if (Http::method() === 'OPTIONS') {
            http_response_code(204);
            exit;
        }
        try {
            if (str_starts_with(Http::path(), '/admin')) {
                Admin::handle(Http::method(), Http::path());
            }
            Http::json(self::route(Http::method(), Http::path()));
        } catch (ApiError $e) {
            Http::json(['error' => $e->errorCode, 'message' => $e->getMessage()], $e->status);
        } catch (\Throwable $e) {
            error_log('[api] ' . $e::class . ': ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
            Http::json([
                'error' => 'server_error',
                'message' => Config::debug() ? $e->getMessage() : 'Something went wrong',
            ], 500);
        }
    }

    private static function route(string $method, string $path): array
    {
        $m = [];
        return match (true) {
            $method === 'GET' && $path === '/health' => ['ok' => true, 'time' => GameService::nowMs()],
            // Where the app finds the WebSocket server; null means it polls instead.
            $method === 'GET' && $path === '/app/update' => AppUpdate::published(),
            $method === 'GET' && $path === '/config' => [
                'ws' => Config::get('WS_PUBLIC_URL') ?: null,
                'facebook' => SupportLinks::config()['facebook'],
                'telegram' => SupportLinks::config()['telegram'],
            ],

            $method === 'POST' && $path === '/auth/guest' => self::guest(),
            $method === 'POST' && $path === '/auth/register' => self::register(),
            $method === 'POST' && $path === '/auth/login' => self::login(),
            $method === 'POST' && $path === '/auth/logout' => self::logout(),
            $method === 'POST' && $path === '/auth/forgot' => self::forgot(),
            $method === 'POST' && $path === '/auth/reset' => self::resetPassword(),

            $method === 'GET' && $path === '/me' => ['user' => Auth::publicUser(Auth::user())],
            $method === 'PATCH' && $path === '/me' => self::updateMe(),
            $method === 'POST' && $path === '/me/avatar' => self::uploadAvatar(),
            $method === 'GET' && $path === '/me/active' => ['match' => GameService::activeFor((int) Auth::user()['id'])],

            // 1v1 challenges between online players.
            $method === 'GET' && $path === '/challenge/online' => ['players' => ChallengeService::online(Auth::user())],
            $method === 'POST' && $path === '/challenge/send' => ChallengeService::send(
                Auth::user(), self::int(Http::body(), 'toUserId'), Http::str('game', 16),
                is_int(Http::body()['level'] ?? null) ? Http::body()['level'] : null
            ),
            $method === 'GET' && $path === '/challenge/inbox' => ChallengeService::inbox(Auth::user()),
            $method === 'POST' && preg_match('#^/challenge/(\\d+)/accept$#', $path, $m) === 1 => self::throttled('rooms', 60, 300, static fn (): array => ChallengeService::accept(Auth::user(), (int) $m[1])),
            $method === 'POST' && preg_match('#^/challenge/(\\d+)/decline$#', $path, $m) === 1 => ChallengeService::decline(Auth::user(), (int) $m[1]),
            $method === 'POST' && preg_match('#^/challenge/(\\d+)/cancel$#', $path, $m) === 1 => ChallengeService::cancel(Auth::user(), (int) $m[1]),

            // Lobby: wallet, bet levels, daily bonus, cue shop - in one call.
            $method === 'GET' && $path === '/lobby' => Economy::lobby(Auth::user()),
            $method === 'POST' && $path === '/daily/claim' => self::throttled('daily', 10, 60, self::claimDaily(...)),
            $method === 'POST' && $path === '/shop/coins/buy' => self::throttled('coin_shop', 30, 3600, self::buyCoinPack(...)),
            $method === 'POST' && $path === '/cues/buy' => self::cue(true),
            $method === 'POST' && $path === '/me/cue' => self::cue(false),
            $method === 'POST' && $path === '/boards/select' => self::selectBoard(),
            $method === 'GET' && $path === '/me/history' => self::history(),
            $method === 'GET' && $path === '/me/activity' => self::activity(),
            $method === 'GET' && $path === '/me/redeems' => self::redeems(),
            $method === 'POST' && $path === '/redeem/request' => self::throttled('redeem', 10, 3600, self::redeemRequest(...)),
            $method === 'POST' && $path === '/deposit/request' => self::throttled('deposit', 15, 3600, self::depositRequest(...)),
            $method === 'GET' && $path === '/notices' => self::notices(),
            $method === 'GET' && $path === '/me/notifications' => self::notifications(),
            $method === 'POST' && $path === '/me/notifications/read' => self::readNotifications(),
            $method === 'POST' && $path === '/me/push-token' => self::pushToken(),
            $method === 'POST' && $path === '/me/push-token/remove' => self::removePushToken(),
            $method === 'GET' && $path === '/referral' => self::referral(),
            $method === 'POST' && $path === '/referral/apply' => self::applyReferral(),

            $method === 'GET' && $path === '/leaderboard' => self::leaderboard(),
            $method === 'POST' && $path === '/matches/bot' => self::throttled('bot', 30, 3600, self::botMatch(...)),

            $method === 'POST' && $path === '/rooms' => self::throttled('rooms', 60, 300, static fn (): array => RoomService::create(
                Auth::user(), Http::str('game', 16), (bool) (Http::body()['private'] ?? false)
            )),
            $method === 'POST' && $path === '/rooms/quick' => self::throttled('rooms', 60, 300, static fn (): array => RoomService::quick(
                Auth::user(), Http::str('game', 16), is_int(Http::body()['level'] ?? null) ? Http::body()['level'] : null
            )),
            $method === 'POST' && $path === '/rooms/join' => self::throttled('rooms', 60, 300, static fn (): array => RoomService::join(Auth::user(), Http::str('code', 6))),
            $method === 'GET' && preg_match('#^/rooms/(\d+)$#', $path, $m) === 1 => RoomService::get((int) $m[1], Auth::user()),
            $method === 'POST' && preg_match('#^/rooms/(\d+)/leave$#', $path, $m) === 1 => RoomService::leave((int) $m[1], Auth::user()),
            $method === 'POST' && preg_match('#^/rooms/(\d+)/rematch$#', $path, $m) === 1 => RoomService::rematch((int) $m[1], Auth::user()),

            $method === 'GET' && preg_match('#^/games/(\d+)$#', $path, $m) === 1 => GameService::get(
                (int) $m[1], (int) Auth::user()['id'], (int) ($_GET['since'] ?? 0)
            ),
            $method === 'POST' && preg_match('#^/games/(\d+)/actions$#', $path, $m) === 1 => GameService::act(
                (int) $m[1], (int) Auth::user()['id'], Http::body()
            ),
            $method === 'POST' && preg_match('#^/games/(\d+)/aim$#', $path, $m) === 1 => self::throttled('aim', 80, 10, static fn (): array => GameService::shareAim(
                (int) $m[1], (int) Auth::user()['id'], Http::body()
            )),

            default => throw ApiError::notFound('No such endpoint'),
        };
    }

    // --------------------------------------------------------------- auth

    /**
     * Runs [$fn] unless this player has hit [$bucket] more than [$limit]
     * times in [$windowSeconds]: a cheap brake on scripted abuse of the
     * endpoints that move coins or create rooms.
     * @param callable(): array<string,mixed> $fn
     * @return array<string,mixed>
     */
    private static function throttled(string $bucket, int $limit, int $windowSeconds, callable $fn): array
    {
        RateLimit::hit($bucket . ':' . Auth::user()['id'], $limit, $windowSeconds);
        return $fn();
    }

    private static function session(int $userId): array
    {
        $user = Db::one('SELECT * FROM users WHERE id = ?', [$userId]);
        return ['token' => Auth::issueToken($userId), 'user' => Auth::publicUser($user)];
    }

    /** An anonymous account, so playing online needs no sign-up. */
    private static function guest(): array
    {
        // Mobile networks put many players behind one address.
        RateLimit::hit('guest:' . RateLimit::ip(), 40, 3600);
        $name = Auth::randomDisplayName();
        $avatar = self::cleanAvatar(Http::str('avatar', 255, false)) ?? 'asset:avatar_1';
        Db::run('INSERT INTO users (display_name, avatar, is_guest, name_set, coins) VALUES (?, ?, 1, 1, 0)', [$name, $avatar]);
        $id = Db::lastId();
        Economy::move($id, (int) Economy::config()['startCoins'], 'welcome');
        return self::session($id);
    }

    /** New account, or - with a guest's token - that guest account gains a login. */
    private static function register(): array
    {
        RateLimit::hit('register:' . RateLimit::ip(), 20, 3600);
        $phone = Phone::normalize(Http::str('phone', 20));
        $password = Http::str('password', 200);
        if (strlen($password) < 8) {
            throw ApiError::badRequest('Password must be at least 8 characters', 'weak_password');
        }
        if (Db::one('SELECT id FROM users WHERE phone = ?', [$phone]) !== null) {
            throw ApiError::conflict('That mobile number is already registered', 'phone_taken');
        }
        $hash = password_hash($password, PASSWORD_DEFAULT);
        if (Http::bearer() !== null) {
            $guest = Auth::user();
            if (!$guest['is_guest']) {
                throw ApiError::conflict('This account already has a login', 'not_guest');
            }
            Db::run('UPDATE users SET phone = ?, password_hash = ?, is_guest = 0, email = NULL WHERE id = ?', [$phone, $hash, $guest['id']]);
            Auth::attachReferral((int) $guest['id'], Http::str('referralCode', 8, false), true);
            return ['token' => Http::bearer(), 'user' => Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$guest['id']]))];
        }
        $name = Auth::randomDisplayName();
        Auth::assertReferralAvailable(Http::str('referralCode', 8, false));
        Db::run('INSERT INTO users (phone, password_hash, display_name, is_guest, name_set, coins) VALUES (?, ?, ?, 0, 1, 0)', [$phone, $hash, $name]);
        $id = Db::lastId();
        Economy::move($id, (int) Economy::config()['startCoins'], 'welcome');
        Auth::attachReferral($id, Http::str('referralCode', 8, false));
        return self::session($id);
    }

    private static function login(): array
    {
        $phone = Phone::normalize(Http::str('phone', 20));
        $password = Http::str('password', 200);
        $ip = RateLimit::ip();
        $recent = (int) Db::one(
            'SELECT COUNT(*) AS n FROM login_attempts WHERE email = ? AND created_at > DATE_SUB(NOW(), INTERVAL 15 MINUTE)',
            [$phone]
        )['n'];
        if ($recent >= 5) {
            throw new ApiError(429, 'too_many_attempts', 'Too many attempts. Try again in 15 minutes.');
        }
        $user = Db::one('SELECT * FROM users WHERE phone = ?', [$phone]);
        if ($user === null || !password_verify($password, (string) $user['password_hash'])) {
            Db::run('INSERT INTO login_attempts (email, ip) VALUES (?, ?)', [$phone, $ip]);
            throw new ApiError(401, 'bad_credentials', 'Wrong mobile number or password');
        }
        Db::run('DELETE FROM login_attempts WHERE email = ?', [$phone]);
        return self::session((int) $user['id']);
    }

    /** Forgot-password SMS OTP only (sign-up has no OTP). Same reply whether the number exists. */
    private static function forgot(): array
    {
        $otpCfg = OtpSms::config();
        if (!$otpCfg['enabled']) {
            throw ApiError::badRequest('Password reset by SMS is turned off. Contact support.', 'forgot_disabled');
        }
        $phone = Phone::normalize(Http::str('phone', 20));
        RateLimit::hit('forgot-ip:' . RateLimit::ip(), (int) $otpCfg['maxPerIpPerHour'], 3600);
        RateLimit::hit('forgot:' . $phone, (int) $otpCfg['maxPerPhonePerHour'], 3600);
        $user = Db::one('SELECT id FROM users WHERE phone = ? AND banned = 0', [$phone]);
        if ($user !== null) {
            $code = OtpSms::generateCode();
            $mins = (int) $otpCfg['validMinutes'];
            Db::run('DELETE FROM password_resets WHERE user_id = ?', [$user['id']]);
            Db::run(
                "INSERT INTO password_resets (user_id, code_hash, expires_at) VALUES (?, ?, DATE_ADD(NOW(), INTERVAL $mins MINUTE))",
                [$user['id'], hash('sha256', $user['id'] . ':' . $code)]
            );
            Sms::sendOtp($phone, $code);
        }
        return ['ok' => true];
    }

    private static function resetPassword(): array
    {
        $digits = (int) OtpSms::config()['otpDigits'];
        $phone = Phone::normalize(Http::str('phone', 20));
        $code = Http::str('code', $digits);
        $password = Http::str('password', 200);
        if (strlen($password) < 8) {
            throw ApiError::badRequest('Password must be at least 8 characters', 'weak_password');
        }
        if (strlen($code) !== $digits || preg_match('/^\d+$/', $code) !== 1) {
            throw ApiError::badRequest('Enter the full OTP from SMS', 'bad_code');
        }
        $bad = new ApiError(400, 'bad_code', 'That code is wrong or has expired');
        $user = Db::one('SELECT id FROM users WHERE phone = ?', [$phone]);
        $reset = $user === null ? null
            : Db::one('SELECT * FROM password_resets WHERE user_id = ? AND expires_at > NOW()', [$user['id']]);
        if ($reset === null || $reset['attempts'] >= 5) {
            throw $bad;
        }
        if (!hash_equals($reset['code_hash'], hash('sha256', $user['id'] . ':' . $code))) {
            Db::run('UPDATE password_resets SET attempts = attempts + 1 WHERE id = ?', [$reset['id']]);
            throw $bad;
        }
        Db::run('UPDATE users SET password_hash = ? WHERE id = ?', [password_hash($password, PASSWORD_DEFAULT), $user['id']]);
        Db::run('DELETE FROM password_resets WHERE user_id = ?', [$user['id']]);
        Db::run('DELETE FROM auth_tokens WHERE user_id = ?', [$user['id']]);
        Db::run('DELETE FROM login_attempts WHERE email = ?', [$phone]);
        return self::session((int) $user['id']);
    }

    private static function logout(): array
    {
        $user = Auth::user();
        Db::run('DELETE FROM auth_tokens WHERE id = ?', [$user['token_id']]);
        return ['ok' => true];
    }

    // ------------------------------------------------------------ profile

    /** Only bundled avatars or this server's own uploads are accepted. */
    private static function cleanAvatar(string $avatar): ?string
    {
        if ($avatar === '') {
            return null;
        }
        if (preg_match('/^asset:avatar_[1-9][0-9]?$/', $avatar) === 1) {
            return $avatar;
        }
        $own = 'url:' . Config::get('APP_URL') . '/uploads/avatars/';
        if (str_starts_with($avatar, $own) && preg_match('#^[\w.\-]+$#', substr($avatar, strlen($own))) === 1) {
            return $avatar;
        }
        throw ApiError::badRequest('Unknown avatar', 'bad_avatar');
    }

    private static function updateMe(): array
    {
        $user = Auth::user();
        Auth::ensureNameChangedColumn();
        $name = Http::str('displayName', 40, false);
        $avatar = self::cleanAvatar(Http::str('avatar', 255, false));
        $skin = Http::str('tableSkin', 32, false);
        if ($skin !== '' && !Economy::poolBoardAllowed((int) $user['id'], $skin)) {
            throw ApiError::badRequest('Unknown table', 'bad_skin');
        }
        if ($name !== '' && preg_match('/^[A-Za-z0-9_]{3,16}$/', $name) !== 1) {
            throw ApiError::badRequest('Use 3-16 letters, numbers or _ for your nickname', 'bad_name');
        }
        $rename = $name !== '' && $name !== (string) $user['display_name'];
        if ($rename) {
            $allowed = Auth::nameChangeAllowedAt($user);
            if ($allowed !== null) {
                throw ApiError::badRequest('You can change your name again after ' . substr($allowed, 0, 10), 'name_cooldown');
            }
        }
        Db::run(
            'UPDATE users SET display_name = ?, avatar = ?, table_skin = ?, name_set = ?, name_changed_at = ? WHERE id = ?',
            [
                $rename ? $name : $user['display_name'],
                $avatar ?? $user['avatar'],
                $skin === '' ? $user['table_skin'] : $skin,
                $rename ? 1 : $user['name_set'],
                $rename ? date('Y-m-d H:i:s') : ($user['name_changed_at'] ?? null),
                $user['id'],
            ]
        );
        return ['user' => Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$user['id']]))];
    }

    private static function uploadAvatar(): array
    {
        $user = Auth::user();
        $file = $_FILES['file'] ?? null;
        if ($file === null || ($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            throw ApiError::badRequest('No image received', 'no_file');
        }
        if ($file['size'] > self::AVATAR_MAX_BYTES) {
            throw ApiError::badRequest('Image must be under 2 MB', 'file_too_large');
        }
        // Trust the bytes, not the client's file name or content type.
        $mime = (new \finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']);
        $ext = self::AVATAR_TYPES[$mime] ?? null;
        if ($ext === null || @getimagesize($file['tmp_name']) === false) {
            throw ApiError::badRequest('Use a JPEG, PNG or WebP image', 'bad_image');
        }
        $dir = dirname(__DIR__) . '/public/uploads/avatars';
        if (!is_dir($dir) && !mkdir($dir, 0755, true) && !is_dir($dir)) {
            throw new \RuntimeException('Upload directory is not writable');
        }
        $name = $user['id'] . '_' . bin2hex(random_bytes(8)) . '.' . $ext;
        if (!move_uploaded_file($file['tmp_name'], "$dir/$name")) {
            throw new \RuntimeException('Could not store the upload');
        }
        $prefix = 'url:' . Config::get('APP_URL') . '/uploads/avatars/';
        if (str_starts_with((string) $user['avatar'], $prefix)) {
            @unlink($dir . '/' . basename(substr($user['avatar'], strlen($prefix))));
        }
        Db::run('UPDATE users SET avatar = ? WHERE id = ?', [$prefix . $name, $user['id']]);
        return ['user' => Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$user['id']]))];
    }

    /** This player's invite code, and what they have earned from it. */
    private static function referral(): array
    {
        $user = Auth::user();
        $public = Auth::publicUser($user);
        return ['code' => $public['referralCode'], 'percent' => (int) Economy::config()['referralPercent'], 'referredBy' => $public['referredBy']]
            + Economy::referralReport((int) $user['id']);
    }

    /** Attach this account to a friend's code. The code is optional at sign-up. */
    private static function applyReferral(): array
    {
        $user = Auth::user();
        $uid = (int) $user['id'];
        RateLimit::hit('referral-apply:' . $uid, 10, 3600);
        RateLimit::hit('referral-apply-ip:' . RateLimit::ip(), 40, 3600);
        Auth::attachReferral($uid, Http::str('code', 12));
        return ['user' => Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$uid]))];
    }

    // -------------------------------------------------------- leaderboard

    private static function leaderboard(): array
    {
        Auth::user();
        $rows = Db::all(
            'SELECT id, display_name, avatar, wins, games, xp FROM users
             WHERE games > 0 AND is_bot = 0 ORDER BY wins DESC, games DESC, id ASC LIMIT 50'
        );
        return ['entries' => array_map(static fn ($r) => [
            'id' => (int) $r['id'], 'name' => $r['display_name'], 'avatar' => $r['avatar'],
            'wins' => (int) $r['wins'], 'games' => (int) $r['games'],
            'level' => Economy::levelOf((int) $r['xp'])['level'], 'rank' => Economy::rankOf((int) $r['wins'])['name'],
        ], $rows)];
    }

    private static function int(array $body, string $key): int
    {
        $v = $body[$key] ?? null;
        if (!is_int($v)) {
            throw ApiError::badRequest("'$key' must be an integer");
        }
        return $v;
    }

    private static function fresh(int $uid): array
    {
        return Auth::publicUser(Db::one('SELECT * FROM users WHERE id = ?', [$uid]));
    }

    private static function buyCoinPack(): array
    {
        $r = CoinShop::buy(Auth::user(), Http::str('id', 32));
        return ['user' => $r['user'], 'receiveCoins' => $r['receiveCoins']];
    }

    private static function claimDaily(): array
    {
        $user = Auth::user();
        $reward = Economy::claimDaily($user);
        $now = Db::one('SELECT * FROM users WHERE id = ?', [$user['id']]);
        return ['reward' => $reward, 'daily' => Economy::dailyStatus($now), 'user' => Auth::publicUser($now)];
    }

    private static function cue(bool $buy): array
    {
        $user = Auth::user();
        $id = Http::str('id', 32);
        $buy ? Economy::buyCue($user, $id) : Economy::equipCue($user, $id);
        return ['user' => self::fresh((int) $user['id'])];
    }

    /** Buy a board if needed, then keep that one selected. */
    private static function selectBoard(): array
    {
        $user = Auth::user();
        Economy::selectBoard($user, Http::str('kind', 16), Http::str('id', 32));
        return ['user' => self::fresh((int) $user['id'])];
    }

    /** The player's latest matches, newest first. */
    private static function history(): array
    {
        $rows = Db::all(
            'SELECT game, mode, won, coins_delta, stake, prize, UNIX_TIMESTAMP(created_at) AS at FROM match_results
             WHERE user_id = ? ORDER BY id DESC LIMIT 40',
            [Auth::user()['id']]
        );
        return ['matches' => array_map(static fn ($r) => [
            'game' => $r['game'], 'mode' => $r['mode'], 'won' => (bool) $r['won'], 'coins' => (int) $r['coins_delta'],
            'stake' => (int) $r['stake'], 'prize' => (int) $r['prize'], 'at' => (int) $r['at'] * 1000,
        ], $rows)];
    }

    /** Matches, coin movements, shop buys and redeem requests — newest first. */
    private static function activity(): array
    {
        $limit = (int) ($_GET['limit'] ?? 60);
        return ['items' => Redeem::activityFeed((int) Auth::user()['id'], $limit)];
    }

    private static function redeems(): array
    {
        return ['requests' => Redeem::listForUser((int) Auth::user()['id'])];
    }

    private static function redeemRequest(): array
    {
        $coins = self::int(Http::body(), 'coins');
        $provider = Http::str('walletProvider', 24);
        $wallet = Http::str('walletNumber', 20);
        return Redeem::create((int) Auth::user()['id'], $coins, $provider, $wallet);
    }

    private static function depositRequest(): array
    {
        $bdt = self::int(Http::body(), 'bdt');
        $provider = Http::str('provider', 24);
        $trxId = Http::str('trxId', 24);
        $payer = Http::str('payerNumber', 20);
        return CoinDeposit::create((int) Auth::user()['id'], $provider, $bdt, $trxId, $payer);
    }

    /** Active operator announcements shown in the app (home banner / inbox). */
    private static function notices(): array
    {
        Auth::user(); // signed-in only
        $rows = Db::all(
            "SELECT id, title, body, kind FROM notices
             WHERE active = 1 AND (expires_at IS NULL OR expires_at > NOW()) ORDER BY id DESC LIMIT 20"
        );
        return ['notices' => array_map(static fn ($r) => [
            'id' => (int) $r['id'], 'title' => $r['title'], 'body' => $r['body'], 'kind' => $r['kind'],
        ], $rows)];
    }

    private static function notifications(): array
    {
        $uid = (int) Auth::user()['id'];
        $after = isset($_GET['after']) && ctype_digit((string) $_GET['after']) ? (int) $_GET['after'] : null;
        $limit = isset($_GET['limit']) && ctype_digit((string) $_GET['limit']) ? (int) $_GET['limit'] : 40;
        $rows = Push::inbox($uid, $limit, $after);
        return [
            'unread' => Push::unreadCount($uid),
            'items' => array_map(static fn (array $r): array => [
                'id' => (int) $r['id'],
                'kind' => $r['kind'],
                'title' => $r['title'],
                'body' => $r['body'],
                'read' => $r['read_at'] !== null,
                'at' => (int) $r['at'] * 1000,
            ], $rows),
        ];
    }

    private static function readNotifications(): array
    {
        $uid = (int) Auth::user()['id'];
        $body = Http::body();
        $id = is_int($body['id'] ?? null) ? $body['id'] : null;
        Push::markRead($uid, $id);
        return ['unread' => Push::unreadCount($uid)];
    }

    private static function pushToken(): array
    {
        $uid = (int) Auth::user()['id'];
        $token = Http::str('token', 512);
        $platform = Http::str('platform', 16, false) ?: 'android';
        Push::registerToken($uid, $token, $platform);
        return ['ok' => true];
    }

    private static function removePushToken(): array
    {
        $uid = (int) Auth::user()['id'];
        Push::removeToken($uid, Http::str('token', 512));
        return ['ok' => true];
    }

    /**
     * Result of a practice match against bots, reported by the app. It cannot
     * be verified, so it pays no coins - only a little experience, at most
     * once every 30 seconds.
     */
    private static function botMatch(): array
    {
        $user = Auth::user();
        $game = Http::str('game', 16);
        if (!isset(RoomService::GAMES[$game]) || $game === 'billiard') {
            throw ApiError::badRequest('Unknown game');
        }
        $won = (bool) (Http::body()['won'] ?? false);
        $recent = Db::one(
            "SELECT id FROM match_results WHERE user_id = ? AND mode = 'bots' AND created_at > DATE_SUB(NOW(), INTERVAL 30 SECOND)",
            [$user['id']]
        );
        if ($recent === null) {
            Db::run("INSERT INTO match_results (user_id, game, mode, won, coins_delta) VALUES (?, ?, 'bots', ?, 0)",
                [$user['id'], $game, $won ? 1 : 0]);
            Db::run('UPDATE users SET xp = xp + ? WHERE id = ?', [$won ? self::BOT_WIN_XP : self::BOT_PLAY_XP, $user['id']]);
        }
        return ['coins' => 0, 'user' => self::fresh((int) $user['id'])];
    }
}
