<?php
declare(strict_types=1);

namespace App;

/**
 * 1v1 challenges between online players: see who is on, send an invite for a
 * game and bet level, the other accepts (buy-ins are taken then) or declines.
 */
final class ChallengeService
{
    /** Games a challenge may be for (all 1 v 1). */
    public const GAMES = ['billiard', 'eight', 'nine', 'ten', 'ludo2', 'carrom'];
    private const TTL_SECONDS = 60;

    /** Online = used a token in the last 3 minutes. */
    private const ONLINE_SQL = "SELECT user_id, MAX(last_used_at) AS la FROM auth_tokens GROUP BY user_id";

    private static function busy(int $uid): bool
    {
        return Db::one(
            "SELECT 1 FROM game_players gp JOIN games g ON g.id = gp.game_id WHERE gp.user_id = ? AND g.status = 'active' LIMIT 1",
            [$uid]
        ) !== null;
    }

    /** @return list<array<string,mixed>> other players who are online now */
    public static function online(array $user): array
    {
        $uid = (int) $user['id'];
        $rows = Db::all(
            "SELECT u.id, u.display_name, u.avatar, u.coins, u.wins, u.xp,
                    EXISTS (SELECT 1 FROM game_players gp JOIN games g ON g.id = gp.game_id
                            WHERE gp.user_id = u.id AND g.status = 'active') AS busy
             FROM users u JOIN (" . self::ONLINE_SQL . ") t ON t.user_id = u.id
             WHERE t.la > DATE_SUB(NOW(), INTERVAL 3 MINUTE) AND u.id <> ? AND u.banned = 0
             ORDER BY busy ASC, t.la DESC LIMIT 60",
            [$uid]
        );
        return array_map(static fn ($r) => [
            'id' => (int) $r['id'], 'name' => $r['display_name'], 'avatar' => $r['avatar'], 'coins' => (int) $r['coins'],
            'level' => Economy::levelOf((int) $r['xp'])['level'], 'rank' => Economy::rankOf((int) $r['wins'])['name'],
            'busy' => (bool) $r['busy'],
        ], $rows);
    }

    public static function send(array $user, int $toUserId, string $game, ?int $level): array
    {
        $uid = (int) $user['id'];
        if ($toUserId === $uid) {
            throw ApiError::badRequest('You cannot challenge yourself');
        }
        if (!in_array($game, self::GAMES, true)) {
            throw ApiError::badRequest('That game cannot be challenged', 'bad_game');
        }
        $target = Db::one('SELECT id, display_name, avatar FROM users WHERE id = ? AND banned = 0', [$toUserId]);
        if ($target === null) {
            throw ApiError::notFound('No such player');
        }
        RateLimit::hit('challenge:' . $uid, 30, 300);
        $bet = $level === null ? ['stake' => 0, 'fee' => 0, 'buyIn' => 0] : Economy::level('billiard', $level);
        if ((int) $user['coins'] < ($bet['buyIn'] ?? 0)) {
            throw ApiError::conflict('Not enough coins for this stake', 'not_enough_coins');
        }
        if (self::busy($uid)) {
            throw ApiError::conflict('Finish your current match first', 'you_busy');
        }
        if (self::busy($toUserId)) {
            throw ApiError::conflict('That player is in a match', 'target_busy');
        }
        return Db::transaction(static function () use ($uid, $toUserId, $game, $level, $bet, $user): array {
            // One live invite at a time between the same two, same direction.
            Db::run(
                "UPDATE challenges SET status = 'cancelled'
                 WHERE from_user = ? AND to_user = ? AND status = 'pending'",
                [$uid, $toUserId]
            );
            Db::run(
                'INSERT INTO challenges (from_user, to_user, game, level, stake, fee, expires_at)
                 VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))',
                [$uid, $toUserId, $game, $level, $bet['stake'] ?? 0, $bet['fee'] ?? 0, self::TTL_SECONDS]
            );
            $id = Db::lastId();
            Push::notifyUser(
                $toUserId,
                'challenge',
                'New challenge',
                ($user['display_name'] ?? 'A player') . ' invited you to a match.'
            );
            return self::view($id);
        });
    }

    /** Pending invites addressed to me, and the live state of ones I sent. */
    public static function inbox(array $user): array
    {
        $uid = (int) $user['id'];
        self::expireOld();
        $incoming = Db::all(
            "SELECT c.*, u.display_name AS from_name, u.avatar AS from_avatar
             FROM challenges c JOIN users u ON u.id = c.from_user
             WHERE c.to_user = ? AND c.status = 'pending' ORDER BY c.id DESC",
            [$uid]
        );
        $outgoing = Db::all(
            "SELECT c.*, u.display_name AS to_name, u.avatar AS to_avatar
             FROM challenges c JOIN users u ON u.id = c.to_user
             WHERE c.from_user = ? AND c.status IN ('pending','accepted')
               AND c.created_at > DATE_SUB(NOW(), INTERVAL 5 MINUTE) ORDER BY c.id DESC",
            [$uid]
        );
        return [
            'incoming' => array_map(self::row(...), $incoming),
            'outgoing' => array_map(self::row(...), $outgoing),
        ];
    }

    public static function accept(array $user, int $id): array
    {
        $uid = (int) $user['id'];
        $c = Db::one('SELECT * FROM challenges WHERE id = ?', [$id]);
        if ($c === null || (int) $c['to_user'] !== $uid) {
            throw ApiError::notFound('Challenge not found');
        }
        if ($c['status'] !== 'pending' || strtotime($c['expires_at']) < time()) {
            throw ApiError::conflict('That challenge is no longer open', 'expired');
        }
        $host = Db::one('SELECT * FROM users WHERE id = ?', [$c['from_user']]);
        if ($host === null) {
            throw ApiError::notFound('Challenger is gone');
        }
        if (self::busy($uid) || self::busy((int) $c['from_user'])) {
            throw ApiError::conflict('A player is already in a match', 'busy');
        }
        // Claim the invite first so two accepts (or an accept racing a cancel)
        // cannot start two matches.
        $claimed = Db::run("UPDATE challenges SET status = 'accepted' WHERE id = ? AND status = 'pending'", [$id])->rowCount();
        if ($claimed !== 1) {
            throw ApiError::conflict('That challenge is no longer open', 'expired');
        }
        try {
            $room = RoomService::matchUp($host, $user, $c['game'], $c['level'] === null ? null : (int) $c['level']);
        } catch (\Throwable $e) {
            Db::run("UPDATE challenges SET status = 'pending' WHERE id = ? AND status = 'accepted' AND room_id IS NULL", [$id]);
            throw $e;
        }
        Db::run('UPDATE challenges SET room_id = ? WHERE id = ?', [$room['id'], $id]);
        return ['room' => $room];
    }

    public static function decline(array $user, int $id): array
    {
        $uid = (int) $user['id'];
        Db::run("UPDATE challenges SET status = 'declined' WHERE id = ? AND to_user = ? AND status = 'pending'", [$id, $uid]);
        return ['ok' => true];
    }

    public static function cancel(array $user, int $id): array
    {
        $uid = (int) $user['id'];
        Db::run("UPDATE challenges SET status = 'cancelled' WHERE id = ? AND from_user = ? AND status = 'pending'", [$id, $uid]);
        return ['ok' => true];
    }

    public static function expireOld(): void
    {
        Db::run("UPDATE challenges SET status = 'expired' WHERE status = 'pending' AND expires_at < NOW()");
    }

    private static function view(int $id): array
    {
        return self::row(Db::one('SELECT * FROM challenges WHERE id = ?', [$id]));
    }

    /** @param array<string,mixed> $c */
    private static function row(array $c): array
    {
        $out = [
            'id' => (int) $c['id'],
            'fromId' => (int) $c['from_user'],
            'toId' => (int) $c['to_user'],
            'game' => $c['game'],
            'level' => $c['level'] === null ? null : (int) $c['level'],
            'stake' => (int) $c['stake'],
            'buyIn' => (int) $c['stake'] + (int) $c['fee'],
            'prize' => (int) $c['stake'] * 2,
            'status' => $c['status'],
            'roomId' => $c['room_id'] === null ? null : (int) $c['room_id'],
            'expiresIn' => max(0, strtotime($c['expires_at']) - time()),
        ];
        if (isset($c['from_name'])) {
            $out['from'] = ['id' => (int) $c['from_user'], 'name' => $c['from_name'], 'avatar' => $c['from_avatar']];
        }
        if (isset($c['to_name'])) {
            $out['to'] = ['id' => (int) $c['to_user'], 'name' => $c['to_name'], 'avatar' => $c['to_avatar']];
        }
        return $out;
    }
}
