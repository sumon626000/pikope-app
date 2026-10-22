<?php
declare(strict_types=1);

namespace App;

/**
 * Money side of the game: bet levels, the house fee, the poker jackpot draw,
 * the cue shop, the daily bonus and player levels. One wallet (`coins`) is
 * shared by every game; every movement is written to `wallet_tx`.
 *
 * The numbers live in the `settings` table (key "economy") so the operator
 * can change them on the admin page; DEFAULTS apply until then.
 */
final class Economy
{
    public const DEFAULTS = [
        // House fee charged on top of the stake, in percent.
        'rakePercent' => 10,
        // Winner prize for pot games (pool, ludo, carrom): stake × seats × (this ÷ 200).
        // 200 = full pot (1v1 stake 100 → win 200). 180 = stake 100 → win 180.
        'winPayoutPercent' => 180,
        // Stake per player at each level. Entry = stake + house fee.
        'billiardStakes' => [25, 50, 100, 300, 500, 1000, 5000, 10000],
        'pokerStakes' => [25, 50, 100, 300, 500, 1000, 5000, 10000],
        'stakeNames' => ['ROOKIE', 'BRONZE', 'SILVER', 'GOLD', 'PLATINUM', 'DIAMOND', 'ROYAL', 'LEGEND'],
        // Billiard poker: the prize is stake x multiplier, drawn per match.
        // Weights are occurrences per 100,000,000 matches.
        'jackpot' => [
            ['x' => 3, 'weight' => 47863970],
            ['x' => 4, 'weight' => 44624020],
            ['x' => 8, 'weight' => 2650000],
            ['x' => 12, 'weight' => 2500000],
            ['x' => 100, 'weight' => 2350000],
            ['x' => 1000, 'weight' => 8000],
            ['x' => 2500, 'weight' => 4000],
            ['x' => 10000, 'weight' => 10],
        ],
        'dailyBonus' => [200, 300, 400, 500, 700, 900, 1500],
        'dailyGems' => [0, 0, 0, 0, 0, 0, 0],
        'startCoins' => 0,
        // Share of a referred player's stake paid to whoever invited them.
        // 1 means 1 coin per 100 of stake. Kept at or below the house fee.
        'referralPercent' => 1,
    ];

    /** Cues are looks only: every cue plays the same, the server decides the physics. */
    public const CUES = [
        'classic' => ['name' => 'Classic Maple', 'price' => 0, 'currency' => 'coins'],
        'ebony' => ['name' => 'Ebony Pro', 'price' => 1500, 'currency' => 'coins'],
        'crimson' => ['name' => 'Crimson Flame', 'price' => 4000, 'currency' => 'coins'],
        'ocean' => ['name' => 'Ocean Wave', 'price' => 7500, 'currency' => 'coins'],
        'emerald' => ['name' => 'Emerald Strike', 'price' => 15000, 'currency' => 'coins'],
        'royal' => ['name' => 'Royal Gold', 'price' => 40000, 'currency' => 'coins'],
        'neon' => ['name' => 'Neon Pulse', 'price' => 60000, 'currency' => 'coins'],
        'dragon' => ['name' => 'Dragon Fury', 'price' => 100000, 'currency' => 'coins'],
    ];

    private const RANKS = ['BRONZE', 'SILVER', 'GOLD', 'PLATINUM', 'DIAMOND'];

    /** @var array<string,mixed>|null */
    private static ?array $config = null;

    /** @return array<string,mixed> */
    public static function config(): array
    {
        if (self::$config === null) {
            $row = Db::one("SELECT v FROM settings WHERE k = 'economy'");
            $saved = $row === null ? [] : (json_decode($row['v'], true) ?: []);
            self::$config = array_merge(self::DEFAULTS, array_intersect_key($saved, self::DEFAULTS));
        }
        return self::$config;
    }

    /**
     * Checks and stores a new configuration (admin page).
     * @param array<string,mixed> $c
     */
    public static function save(array $c): void
    {
        $rake = $c['rakePercent'] ?? null;
        if (!is_int($rake) && !is_float($rake) || $rake < 0 || $rake > 50) {
            throw ApiError::badRequest('rakePercent must be between 0 and 50');
        }
        foreach (['billiardStakes', 'pokerStakes'] as $key) {
            $list = $c[$key] ?? null;
            if (!is_array($list) || !array_is_list($list) || count($list) !== 8) {
                throw ApiError::badRequest("$key must be exactly 8 stake amounts");
            }
            foreach ($list as $v) {
                if (!is_int($v) || $v < 1 || $v > 100000000) {
                    throw ApiError::badRequest("$key must hold whole numbers above zero");
                }
            }
        }
        $names = $c['stakeNames'] ?? null;
        if (!is_array($names) || !array_is_list($names) || count($names) !== 8) {
            throw ApiError::badRequest('stakeNames must be exactly 8 labels');
        }
        $c['stakeNames'] = array_map(static function ($raw): string {
            $s = strtoupper(preg_replace('/[^A-Za-z0-9 _-]/', '', trim((string) $raw)) ?? '');
            return substr($s === '' ? 'LEVEL' : $s, 0, 16);
        }, $names);
        foreach (['dailyBonus', 'dailyGems'] as $key) {
            $list = $c[$key] ?? null;
            if (!is_array($list) || !array_is_list($list) || $list === [] || count($list) > 12) {
                throw ApiError::badRequest("$key must be a list of 1-12 numbers");
            }
            foreach ($list as $v) {
                if (!is_int($v) || $v < 0 || $v > 100000000 || ($v === 0 && $key !== 'dailyGems')) {
                    throw ApiError::badRequest("$key must hold whole numbers above zero");
                }
            }
        }
        if (count($c['dailyBonus']) !== count($c['dailyGems'])) {
            throw ApiError::badRequest('dailyBonus and dailyGems must have the same length');
        }
        $jackpot = $c['jackpot'] ?? null;
        if (!is_array($jackpot) || !array_is_list($jackpot) || $jackpot === [] || count($jackpot) > 16) {
            throw ApiError::badRequest('jackpot must be a list of {x, weight}');
        }
        foreach ($jackpot as $j) {
            if (!is_array($j) || !is_int($j['x'] ?? null) || !is_int($j['weight'] ?? null)
                || $j['x'] < 1 || $j['x'] > 1000000 || $j['weight'] < 1) {
                throw ApiError::badRequest('each jackpot entry needs whole numbers x >= 1 and weight >= 1');
            }
        }
        $start = $c['startCoins'] ?? null;
        if (!is_int($start) || $start < 0 || $start > 100000000) {
            throw ApiError::badRequest('startCoins must be a whole number');
        }
        $winPay = $c['winPayoutPercent'] ?? 200;
        if (!is_int($winPay) || $winPay < 50 || $winPay > 300) {
            throw ApiError::badRequest('winPayoutPercent must be between 50 and 300');
        }
        $referral = $c['referralPercent'] ?? 0;
        if (!is_int($referral) || $referral < 0 || $referral > 50) {
            throw ApiError::badRequest('referralPercent must be a whole number from 0 to 50');
        }
        if ($referral > $rake) {
            throw ApiError::badRequest('referralPercent cannot be higher than the house fee percent');
        }
        $clean = array_intersect_key($c, self::DEFAULTS);
        Db::run("INSERT INTO settings (k, v) VALUES ('economy', ?) ON DUPLICATE KEY UPDATE v = VALUES(v)", [json_encode($clean)]);
        self::$config = null;
    }

    public static function fee(int $stake): int
    {
        return (int) ceil($stake * self::config()['rakePercent'] / 100);
    }

    /** Winner prize in staked pot games (not billiard poker jackpot). */
    public static function winnerPrize(int $stake, int $seats): int
    {
        if ($stake <= 0 || $seats <= 0) {
            return 0;
        }
        $p = (int) self::config()['winPayoutPercent'];
        $full = $stake * $seats;
        $prize = intdiv($stake * $seats * $p, 200);
        return min($full, max(0, $prize));
    }

    /** Coins owed to a referrer for one player's stake. Fractions are dropped. */
    public static function referralCut(int $stake): int
    {
        $percent = (int) self::config()['referralPercent'];
        if ($percent <= 0 || $stake <= 0) {
            return 0;
        }
        return intdiv($stake * $percent, 100);
    }

    /**
     * Pays whoever invited this player, from the house, when a staked match
     * starts. No-op for bots, players with no inviter, or a cut below 1 coin.
     */
    public static function payReferral(int $playerId, int $stake, int $roomId): void
    {
        $cut = self::referralCut($stake);
        if ($cut <= 0) {
            return;
        }
        $row = Db::one('SELECT referred_by, is_bot, is_guest FROM users WHERE id = ?', [$playerId]);
        if ($row === null || (int) $row['is_bot'] === 1 || (int) $row['is_guest'] === 1) {
            return;
        }
        $referrerId = (int) ($row['referred_by'] ?? 0);
        if ($referrerId <= 0 || $referrerId === $playerId) {
            return;
        }
        $referrer = Db::one('SELECT id, banned, is_bot FROM users WHERE id = ?', [$referrerId]);
        if ($referrer === null || (int) $referrer['banned'] === 1 || (int) $referrer['is_bot'] === 1) {
            return;
        }
        self::move($referrerId, $cut, 'referral', $roomId);
        Db::run('UPDATE wallet_tx SET ref_user_id = ? WHERE id = ?', [$playerId, Db::lastId()]);
    }

    /**
     * One player's invite results: how many accounts they brought, what those
     * matches paid today, this month and in total, and the list of people.
     * @return array{invited:int,earned:int,earnedToday:int,earnedMonth:int,people:list<array<string,mixed>>}
     */
    public static function referralReport(int $userId): array
    {
        $sum = static function (string $when) use ($userId): int {
            return (int) Db::one(
                "SELECT COALESCE(SUM(amount), 0) AS n FROM wallet_tx
                 WHERE user_id = ? AND reason = 'referral' $when",
                [$userId]
            )['n'];
        };
        $people = Db::all(
            "SELECT u.id, u.display_name, u.created_at, u.is_guest, u.games,
                    COALESCE((SELECT SUM(t.amount) FROM wallet_tx t
                              WHERE t.user_id = ? AND t.reason = 'referral' AND t.ref_user_id = u.id), 0) AS earned
             FROM users u WHERE u.referred_by = ? ORDER BY u.id DESC",
            [$userId, $userId]
        );
        return [
            'invited' => count($people),
            'earned' => $sum(''),
            'earnedToday' => $sum('AND created_at >= CURDATE()'),
            'earnedMonth' => $sum("AND created_at >= DATE_FORMAT(NOW(), '%Y-%m-01')"),
            'people' => array_map(static fn (array $p): array => [
                'id' => (int) $p['id'],
                'name' => $p['display_name'],
                'joined' => $p['created_at'],
                'guest' => (int) $p['is_guest'] === 1,
                'games' => (int) $p['games'],
                'earned' => (int) $p['earned'],
            ], $people),
        ];
    }

    /**
     * Bet levels of one mode ("billiard" or "poker") as the app shows them.
     * @return list<array<string,mixed>>
     */
    public static function levels(string $mode): array
    {
        $c = self::config();
        $out = [];
        $names = self::config()['stakeNames'] ?? self::DEFAULTS['stakeNames'];
        foreach ($c[$mode === 'poker' ? 'pokerStakes' : 'billiardStakes'] as $i => $stake) {
            $fee = self::fee($stake);
            $level = [
                'level' => $i,
                'name' => (string) ($names[$i] ?? ('LEVEL ' . ($i + 1))),
                'stake' => $stake,
                'fee' => $fee,
                'buyIn' => $stake + $fee,
            ];
            if ($mode === 'poker') {
                $xs = array_column($c['jackpot'], 'x');
                $level += ['minPrize' => $stake * min($xs), 'maxPrize' => $stake * max($xs)];
            } else {
                $level += ['prize' => self::winnerPrize($stake, 2)];
            }
            $out[] = $level;
        }
        return $out;
    }

    /** @return array{stake:int,fee:int,buyIn:int} */
    public static function level(string $mode, int $index): array
    {
        $levels = self::levels($mode);
        if (!isset($levels[$index])) {
            throw ApiError::badRequest('Unknown bet level', 'bad_level');
        }
        return $levels[$index];
    }

    /** The prize multiplier of one poker match, drawn with the configured odds. */
    public static function drawMultiplier(): int
    {
        $table = self::config()['jackpot'];
        $total = array_sum(array_column($table, 'weight'));
        $roll = random_int(1, $total);
        foreach ($table as $entry) {
            $roll -= $entry['weight'];
            if ($roll <= 0) {
                return $entry['x'];
            }
        }
        return $table[0]['x'];
    }

    /**
     * Moves coins (or gems) and records it. The caller holds the transaction;
     * the user row is locked here. Refuses to go below zero.
     *
     * Coins also track redeemable_coins: deposits stay in the main wallet only;
     * prizes and referrals add redeemable balance; cash-out uses redeemable only;
     * buy-ins spend non-redeemable coins first.
     */
    public static function move(int $uid, int $amount, string $reason, ?int $roomId = null, string $currency = 'coins'): int
    {
        if ($currency === 'gems') {
            $row = Db::one('SELECT gems AS balance FROM users WHERE id = ? FOR UPDATE', [$uid]);
            $balance = (int) $row['balance'] + $amount;
            if ($balance < 0) {
                throw ApiError::conflict('Not enough gems', 'not_enough_gems');
            }
            Db::run('UPDATE users SET gems = ? WHERE id = ?', [$balance, $uid]);
            Db::run('INSERT INTO wallet_tx (user_id, currency, amount, balance_after, reason, room_id) VALUES (?, ?, ?, ?, ?, ?)',
                [$uid, 'gems', $amount, $balance, $reason, $roomId]);
            return $balance;
        }

        self::ensureRedeemableColumn();
        $row = Db::one('SELECT coins, redeemable_coins FROM users WHERE id = ? FOR UPDATE', [$uid]);
        $coins = (int) $row['coins'];
        $redeemable = (int) $row['redeemable_coins'];

        if ($amount >= 0) {
            $coins += $amount;
            if (self::creditsRedeemable($reason)) {
                $redeemable += $amount;
            }
        } else {
            $debit = -$amount;
            if ($debit > $coins) {
                throw ApiError::conflict('Not enough coins', 'not_enough_coins');
            }
            if (self::isRedeemWithdrawal($reason)) {
                if ($debit > $redeemable) {
                    throw ApiError::conflict('Only win balance can be redeemed. Add more by winning matches.', 'not_enough_redeemable');
                }
                $redeemable -= $debit;
            } else {
                $nonRedeemable = max(0, $coins - $redeemable);
                $fromDeposit = min($debit, $nonRedeemable);
                $fromWin = $debit - $fromDeposit;
                $redeemable -= $fromWin;
            }
            $coins -= $debit;
        }

        if ($redeemable < 0 || $redeemable > $coins) {
            throw new ApiError(500, 'server_error', 'Wallet balance mismatch');
        }

        Db::run('UPDATE users SET coins = ?, redeemable_coins = ? WHERE id = ?', [$coins, $redeemable, $uid]);
        Db::run('INSERT INTO wallet_tx (user_id, currency, amount, balance_after, reason, room_id) VALUES (?, ?, ?, ?, ?, ?)',
            [$uid, 'coins', $amount, $coins, $reason, $roomId]);
        Push::notifyWalletChange($uid, $amount, $reason, $roomId);
        return $coins;
    }

    /** Winnings (and redeem refunds) increase the cash-out bucket. */
    private static function creditsRedeemable(string $reason): bool
    {
        return $reason === 'prize'
            || $reason === 'referral'
            || str_starts_with($reason, 'redeem_refund:');
    }

    /** Pending/approved redeem holds — must not spend deposited coins. */
    private static function isRedeemWithdrawal(string $reason): bool
    {
        return str_starts_with($reason, 'redeem:') && !str_starts_with($reason, 'redeem_refund:');
    }

    /** Adds users.redeemable_coins and backfills from wallet history once. */
    public static function ensureRedeemableColumn(): void
    {
        static $done = false;
        if ($done) {
            return;
        }
        $done = true;
        $have = Db::pdo()->query("SHOW COLUMNS FROM users LIKE 'redeemable_coins'")->fetch();
        if ($have !== false) {
            return;
        }
        Db::pdo()->exec('ALTER TABLE users ADD COLUMN redeemable_coins INT NOT NULL DEFAULT 0 AFTER coins');
        foreach (Db::all('SELECT id, coins FROM users') as $u) {
            $uid = (int) $u['id'];
            $earned = (int) Db::one(
                "SELECT COALESCE(SUM(amount), 0) AS n FROM wallet_tx
                 WHERE user_id = ? AND currency = 'coins' AND amount > 0
                 AND (reason = 'prize' OR reason = 'referral' OR reason LIKE 'redeem_refund:%')",
                [$uid]
            )['n'];
            $redeemOut = (int) Db::one(
                "SELECT COALESCE(SUM(-amount), 0) AS n FROM wallet_tx
                 WHERE user_id = ? AND currency = 'coins' AND amount < 0 AND reason LIKE 'redeem:%'",
                [$uid]
            )['n'];
            $redeemable = min((int) $u['coins'], max(0, $earned - $redeemOut));
            Db::run('UPDATE users SET redeemable_coins = ? WHERE id = ?', [$redeemable, $uid]);
        }
    }

    // ------------------------------------------------------------ levels

    /** @return array{level:int,progress:int} progress in percent to the next level */
    public static function levelOf(int $xp): array
    {
        // Level n starts at 100 * (n-1)^2 XP: quick early levels, slower later.
        $level = (int) floor(sqrt(max(0, $xp) / 100)) + 1;
        $from = 100 * ($level - 1) ** 2;
        $to = 100 * $level ** 2;
        return ['level' => $level, 'progress' => (int) floor(100 * ($xp - $from) / ($to - $from))];
    }

    /** Rank badge from online wins, e.g. "GOLD III". */
    public static function rankOf(int $wins): array
    {
        $step = min(count(self::RANKS) * 3 - 1, intdiv($wins, 5));
        return ['tier' => intdiv($step, 3), 'name' => self::RANKS[intdiv($step, 3)] . ' ' . ['I', 'II', 'III'][$step % 3]];
    }

    // -------------------------------------------------------- daily bonus

    /** @param array<string,mixed> $user @return array<string,mixed> */
    public static function dailyStatus(array $user): array
    {
        $c = self::config();
        $days = count($c['dailyBonus']);
        $last = $user['daily_claimed_on'];
        $today = date('Y-m-d');
        $streak = (int) $user['daily_streak'];
        // A missed day starts the ladder again.
        if ($last !== null && $last !== $today && $last !== date('Y-m-d', strtotime('-1 day'))) {
            $streak = 0;
        }
        $available = $last !== $today;
        $day = $streak % $days;
        return [
            'available' => $available,
            'day' => $available ? $day : ($streak - 1 + $days) % $days,
            'rewards' => array_map(static fn (int $coins, int $gems): array => ['coins' => $coins, 'gems' => $gems],
                $c['dailyBonus'], $c['dailyGems']),
            'secondsToNext' => $available ? 0 : max(0, strtotime('tomorrow') - time()),
        ];
    }

    /** @param array<string,mixed> $user @return array{coins:int,gems:int} */
    public static function claimDaily(array $user): array
    {
        return Db::transaction(static function () use ($user): array {
            $row = Db::one('SELECT * FROM users WHERE id = ? FOR UPDATE', [$user['id']]);
            $status = self::dailyStatus($row);
            if (!$status['available']) {
                throw ApiError::conflict('Come back tomorrow for the next bonus', 'already_claimed');
            }
            $reward = $status['rewards'][$status['day']];
            $last = $row['daily_claimed_on'];
            $streak = $last === date('Y-m-d', strtotime('-1 day')) ? (int) $row['daily_streak'] + 1 : 1;
            Db::run('UPDATE users SET daily_claimed_on = ?, daily_streak = ? WHERE id = ?', [date('Y-m-d'), $streak, $row['id']]);
            self::move((int) $row['id'], $reward['coins'], 'daily_bonus');
            if ($reward['gems'] > 0) {
                self::move((int) $row['id'], $reward['gems'], 'daily_bonus', null, 'gems');
            }
            return $reward;
        });
    }

    // ---------------------------------------------------------------- cues

    /** @return list<string> */
    public static function ownedCues(int $uid): array
    {
        $rows = Db::all("SELECT item FROM user_items WHERE user_id = ? AND kind = 'cue'", [$uid]);
        return array_values(array_unique(array_merge(['classic'], array_column($rows, 'item'))));
    }

    public static function buyCue(array $user, string $id): void
    {
        $cue = ItemCatalog::cue($id);
        Db::transaction(static function () use ($user, $id, $cue): void {
            $uid = (int) $user['id'];
            Db::one('SELECT id FROM users WHERE id = ? FOR UPDATE', [$uid]);
            if (in_array($id, self::ownedCues($uid), true)) {
                throw ApiError::conflict('You already own this cue', 'already_owned');
            }
            if ($cue['price'] > 0) {
                self::move($uid, -$cue['price'], 'cue:' . $id, null, $cue['currency']);
            }
            Db::run("INSERT INTO user_items (user_id, kind, item) VALUES (?, 'cue', ?)", [$uid, $id]);
            Db::run('UPDATE users SET cue = ? WHERE id = ?', [$id, $uid]);
        });
    }

    public static function equipCue(array $user, string $id): void
    {
        if (!in_array($id, self::ownedCues((int) $user['id']), true)) {
            throw ApiError::conflict('You do not own this cue', 'not_owned');
        }
        Db::run('UPDATE users SET cue = ? WHERE id = ?', [$id, $user['id']]);
    }

    // -------------------------------------------------------------- boards

    /**
     * Cloth prices in Pico coin. 0 is free and always owned.
     * Keep these in step with the app shop (board_shop.dart, ludo_board.dart).
     *
     * @var array<string, array<string, int>>
     */
    public const BOARDS = [
        'pool' => [
            'pro_teal' => 0, 'pro_green' => 0, 'pro_blue' => 0,
            'pro_red' => 2000, 'pro_black' => 4000,
            'table2' => 6000, 'table1' => 8000, 'table3' => 10000,
            'table4' => 12000, 'table5' => 14000, 'table6' => 16000, 'table8' => 18000,
        ],
        'carrom' => [
            'classic' => 0, 'walnut' => 0,
            'royal' => 4000, 'emerald' => 6000, 'cherry' => 8000, 'midnight' => 12000,
        ],
        'ludo' => [
            'classic' => 0, 'royal' => 5000, 'sunset' => 8000, 'midnight' => 12000, 'candy' => 15000,
        ],
    ];

    public static function ensureBoardColumns(): void
    {
        static $done = false;
        if ($done) {
            return;
        }
        $done = true;
        foreach (['carrom_board' => 'classic', 'ludo_board' => 'classic'] as $col => $def) {
            $have = Db::pdo()->query("SHOW COLUMNS FROM users LIKE " . Db::pdo()->quote($col))->fetch();
            if ($have === false) {
                Db::pdo()->exec("ALTER TABLE users ADD COLUMN $col VARCHAR(32) NOT NULL DEFAULT '$def'");
            }
        }
    }

    /** @return list<string> */
    public static function ownedBoards(int $uid, string $kind): array
    {
        $catalog = ItemCatalog::boards()[$kind] ?? [];
        $free = [];
        foreach ($catalog as $id => $price) {
            if ($price === 0) {
                $free[] = $id;
            }
        }
        $rows = Db::all('SELECT item FROM user_items WHERE user_id = ? AND kind = ?', [$uid, $kind]);
        return array_values(array_unique(array_merge($free, array_column($rows, 'item'))));
    }

    /** A pool cloth the profile editor may save: known, and already paid for. */
    public static function poolBoardAllowed(int $uid, string $id): bool
    {
        $price = ItemCatalog::boards()['pool'][$id] ?? null;
        if ($price === null) {
            return false;
        }
        return $price === 0 || in_array($id, self::ownedBoards($uid, 'pool'), true);
    }

    /** Buy [id] of [kind] when it is not owned yet, then leave it selected. */
    public static function selectBoard(array $user, string $kind, string $id): void
    {
        self::ensureBoardColumns();
        $price = ItemCatalog::boardPrice($kind, $id);
        $column = match ($kind) {
            'pool' => 'table_skin',
            'carrom' => 'carrom_board',
            'ludo' => 'ludo_board',
            default => throw ApiError::notFound('No such board'),
        };
        Db::transaction(static function () use ($user, $kind, $id, $price, $column): void {
            $uid = (int) $user['id'];
            Db::one('SELECT id FROM users WHERE id = ? FOR UPDATE', [$uid]);
            if (!in_array($id, self::ownedBoards($uid, $kind), true)) {
                if ($price > 0) {
                    self::move($uid, -$price, 'board:' . $kind . ':' . $id);
                }
                Db::run('INSERT INTO user_items (user_id, kind, item) VALUES (?, ?, ?)', [$uid, $kind, $id]);
            }
            Db::run("UPDATE users SET $column = ? WHERE id = ?", [$id, $uid]);
        });
    }

    // --------------------------------------------------------------- lobby

    /** Everything the lobby screens need in one request. @param array<string,mixed> $user */
    public static function lobby(array $user): array
    {
        $waiting = [];
        foreach (Db::all("SELECT r.game, r.level, COUNT(*) AS n FROM rooms r JOIN room_players p ON p.room_id = r.id
                          WHERE r.status = 'waiting' AND r.level IS NOT NULL GROUP BY r.game, r.level") as $row) {
            $waiting[($row['game'] === 'poker' ? 'poker' : 'billiard') . ':' . $row['level']] = (int) $row['n'];
        }
        $online = (int) Db::one('SELECT COUNT(DISTINCT user_id) AS n FROM auth_tokens WHERE last_used_at > DATE_SUB(NOW(), INTERVAL 3 MINUTE)')['n'];
        $playing = [];
        foreach (Db::all("SELECT r.game, r.level, COUNT(*) AS n FROM rooms r JOIN room_players p ON p.room_id = r.id
                          WHERE r.status = 'playing' AND r.level IS NOT NULL AND r.updated_at > DATE_SUB(NOW(), INTERVAL 2 HOUR)
                          GROUP BY r.game, r.level") as $row) {
            $key = ($row['game'] === 'poker' ? 'poker' : 'billiard') . ':' . $row['level'];
            $playing[$key] = ($playing[$key] ?? 0) + (int) $row['n'];
        }
        $levels = [];
        foreach (['billiard', 'poker'] as $mode) {
            $levels[$mode] = array_map(static fn (array $l): array => $l + [
                'players' => ($waiting["$mode:{$l['level']}"] ?? 0) + ($playing["$mode:{$l['level']}"] ?? 0),
            ], self::levels($mode));
        }
        $owned = self::ownedCues((int) $user['id']);
        $cues = [];
        foreach (Economy::CUES as $id => $cue) {
            $live = ItemCatalog::cue($id);
            $cues[] = [
                'id' => $id,
                'name' => $live['name'],
                'price' => $live['price'],
                'currency' => $live['currency'],
                'owned' => in_array($id, $owned, true),
            ];
        }
        return [
            'user' => Auth::publicUser($user),
            'online' => $online,
            'rakePercent' => self::config()['rakePercent'],
            'levels' => $levels,
            'jackpot' => array_column(self::config()['jackpot'], 'x'),
            'daily' => self::dailyStatus($user),
            'cues' => $cues,
            'boardPrices' => ItemCatalog::boards(),
            'coinShop' => [
                'globalDiscountPercent' => 0,
                'packs' => CoinShop::publicPacks((int) $user['id']),
            ],
            'redeem' => Redeem::publicConfig(),
            'coinTransfer' => CoinTransfer::publicConfig(),
            'coinDeposit' => CoinDeposit::publicConfig(),
            'promotions' => Promotions::publicConfig(),
            'push' => [
                'enabled' => (bool) Push::config()['enabled'],
                'channelId' => Push::config()['channelId'],
                'channelName' => Push::config()['channelName'],
            ],
        ];
    }
}
