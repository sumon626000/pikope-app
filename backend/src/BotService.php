<?php
declare(strict_types=1);

namespace App;

/**
 * Stand-in players for free public quick match only (stake 0). Staked / real-coin
 * rooms never get bots. When nobody joins within BOT_FILL_SECONDS (default 5),
 * bots take empty seats. bin/bot-worker.php drives them.
 */
final class BotService
{
    private const NAMES = [
        'Rafi_Pro', 'Nadia22', 'KingAyan', 'Sumon_X', 'Tania_Q', 'Arif007', 'MimiStar', 'Shuvo_K',
        'Rakib_99', 'Priya_M', 'Jamil_T', 'Sadia_R', 'Fahim_Ace', 'Nusrat_B', 'Imran_Z', 'Lamia_J',
    ];
    private const AVATARS = ['asset:avatar_1', 'asset:avatar_2', 'asset:avatar_3', 'asset:avatar_4', 'asset:avatar_5', 'asset:avatar_6'];

    /** A bot's wallet is refilled to this when it falls below a few buy-ins. */
    private const BANKROLL = 500000;

    public static function enabled(): bool
    {
        return Config::get('BOT_FILL', '1') === '1';
    }

    public static function fillSeconds(): int
    {
        return max(1, Config::int('BOT_FILL_SECONDS', 5));
    }

    /** Creates any missing bot accounts. */
    public static function ensure(): void
    {
        $have = array_column(Db::all('SELECT display_name FROM users WHERE is_bot = 1'), 'display_name');
        foreach (self::NAMES as $i => $name) {
            if (in_array($name, $have, true)) {
                continue;
            }
            Db::run(
                'INSERT INTO users (display_name, avatar, coins, xp, is_guest, is_bot, name_set) VALUES (?, ?, ?, ?, 0, 1, 1)',
                [$name, self::AVATARS[$i % count(self::AVATARS)], self::BANKROLL, random_int(300, 9000)]
            );
        }
    }

    /** Seats bots in every public room that has waited long enough. Returns how many started. */
    public static function fillRooms(): int
    {
        if (!self::enabled()) {
            return 0;
        }
        $rows = Db::all(
            "SELECT r.id FROM rooms r WHERE r.status = 'waiting' AND r.is_private = 0
               AND r.stake = 0 AND r.fee = 0 AND r.level IS NULL
               AND EXISTS (SELECT 1 FROM room_players p WHERE p.room_id = r.id
                           AND p.joined_at <= DATE_SUB(NOW(), INTERVAL ? SECOND))",
            [self::fillSeconds()]
        );
        $started = 0;
        foreach ($rows as $row) {
            if (RoomService::fillWithBots((int) $row['id'])) {
                $started++;
            }
        }
        return $started;
    }

    /**
     * $count bot users who can pay $buyIn, least busy first, none of $exclude.
     * Call inside the room's transaction.
     * @param list<int> $exclude @return list<array<string,mixed>>
     */
    public static function pick(int $count, int $buyIn, array $exclude): array
    {
        self::ensure();
        $not = $exclude === [] ? '' : ' AND u.id NOT IN (' . implode(',', array_map('intval', $exclude)) . ')';
        $rows = Db::all(
            "SELECT u.id FROM users u WHERE u.is_bot = 1 AND u.banned = 0$not
             ORDER BY (SELECT COUNT(*) FROM game_players gp JOIN games g ON g.id = gp.game_id
                       WHERE gp.user_id = u.id AND g.status = 'active'), RAND()
             LIMIT " . max(0, $count)
        );
        $bots = [];
        foreach ($rows as $row) {
            $id = (int) $row['id'];
            $coins = (int) Db::one('SELECT coins FROM users WHERE id = ? FOR UPDATE', [$id])['coins'];
            if ($coins < max(5 * $buyIn, 20000)) {
                Economy::move($id, self::BANKROLL - $coins + 5 * $buyIn, 'bot_topup');
            }
            $bots[] = Db::one('SELECT * FROM users WHERE id = ?', [$id]);
        }
        return $bots;
    }
}
