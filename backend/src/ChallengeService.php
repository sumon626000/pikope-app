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
    public const GAMES = ['billiard', 'eight', 'nine', 'ten', 'ludo2', 'ludo4', 'carrom'];
    private const TTL_SECONDS = 60;
    private const OPEN_INVITE_SECONDS = 120;

    /** pool | ludo | carrom — settings and accept checks use these families. */
    public static function gameFamily(string $game): ?string
    {
        if (str_starts_with($game, 'ludo')) {
            return 'ludo';
        }
        if ($game === 'carrom') {
            return 'carrom';
        }
        if (in_array($game, ['billiard', 'eight', 'nine', 'ten', 'poker'], true)) {
            return 'pool';
        }
        return null;
    }

    /** Whether this user accepts an incoming invite for [game]. */
    public static function userAcceptsGame(array $u, string $game): bool
    {
        Auth::ensureChallengesEnabledColumn();
        Auth::ensureChallengeGameColumns();
        if (!(bool) ($u['challenges_enabled'] ?? 1)) {
            return false;
        }
        $family = self::gameFamily($game);
        if ($family === null) {
            return false;
        }
        $col = match ($family) {
            'pool' => 'challenge_pool',
            'ludo' => 'challenge_ludo',
            'carrom' => 'challenge_carrom',
        };
        return (bool) ($u[$col] ?? 1);
    }

    /** @param array<string,mixed> $u */
    public static function userAcceptsAny(array $u): bool
    {
        return self::userAcceptsGame($u, 'billiard')
            || self::userAcceptsGame($u, 'ludo2')
            || self::userAcceptsGame($u, 'carrom');
    }

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
        Auth::ensureChallengesEnabledColumn();
        Auth::ensureChallengeGameColumns();
        $rows = Db::all(
            "SELECT u.id, u.display_name, u.avatar, u.coins, u.wins, u.xp, u.challenges_enabled,
                    u.challenge_pool, u.challenge_ludo, u.challenge_carrom,
                    EXISTS (SELECT 1 FROM game_players gp JOIN games g ON g.id = gp.game_id
                            WHERE gp.user_id = u.id AND g.status = 'active') AS busy,
                    (SELECT g.game FROM game_players gp JOIN games g ON g.id = gp.game_id
                     WHERE gp.user_id = u.id AND g.status = 'active' LIMIT 1) AS active_game,
                    (SELECT r.game FROM room_players rp JOIN rooms r ON r.id = rp.room_id
                     WHERE rp.user_id = u.id AND r.status = 'waiting' LIMIT 1) AS waiting_game
             FROM users u JOIN (" . self::ONLINE_SQL . ") t ON t.user_id = u.id
             WHERE t.la > DATE_SUB(NOW(), INTERVAL 3 MINUTE) AND u.id <> ? AND u.banned = 0
             ORDER BY busy ASC, t.la DESC LIMIT 60",
            [$uid]
        );
        return array_map(static function ($r) {
            $busy = (bool) $r['busy'];
            $game = $busy ? (string) ($r['active_game'] ?? '') : (string) ($r['waiting_game'] ?? '');
            return [
                'id' => (int) $r['id'], 'name' => $r['display_name'], 'avatar' => $r['avatar'], 'coins' => (int) $r['coins'],
                'level' => Economy::levelOf((int) $r['xp'])['level'], 'rank' => Economy::rankOf((int) $r['wins'])['name'],
                'busy' => $busy,
                'game' => $game,
                'acceptsChallenges' => self::userAcceptsAny($r),
            ];
        }, $rows);
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
        if ($level === null) {
            throw ApiError::badRequest('Pick a stake level', 'bad_level');
        }
        Auth::ensureChallengesEnabledColumn();
        Auth::ensureChallengeGameColumns();
        $target = Db::one(
            'SELECT id, display_name, avatar, challenges_enabled, challenge_pool, challenge_ludo, challenge_carrom
             FROM users WHERE id = ? AND banned = 0',
            [$toUserId]
        );
        if ($target === null) {
            throw ApiError::notFound('No such player');
        }
        if (!self::userAcceptsGame($target, $game)) {
            throw ApiError::conflict('That player is not accepting challenges for this game', 'challenges_off');
        }
        RateLimit::hit('challenge:' . $uid, 30, 300);
        $stakeMode = $game === 'poker' ? 'poker' : 'billiard';
        $bet = $level === null ? ['stake' => 0, 'fee' => 0, 'buyIn' => 0] : Economy::level($stakeMode, $level);
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
                ($user['display_name'] ?? 'A player') . ' invited you to a match.',
                ['game' => $game],
                'challenge:' . $id
            );
            return self::view($id);
        });
    }

    /** When someone opens a public table, notify every eligible online player. */
    public static function broadcastOpenMatch(array $user, array $roomView): void
    {
        $uid = (int) $user['id'];
        $roomId = (int) ($roomView['id'] ?? 0);
        if ($roomId < 1 || ($roomView['status'] ?? '') !== 'waiting' || !empty($roomView['isPrivate'])) {
            return;
        }
        $game = (string) ($roomView['game'] ?? '');
        if (!in_array($game, self::GAMES, true) && $game !== 'poker') {
            return;
        }
        if ($game === 'poker') {
            return;
        }
        RateLimit::hit('open-ch:' . $uid, 12, 60);
        self::cancelPendingForRoom($roomId);
        $level = isset($roomView['level']) && $roomView['level'] !== null ? (int) $roomView['level'] : null;
        $stake = (int) ($roomView['stake'] ?? 0);
        $fee = (int) ($roomView['fee'] ?? 0);
        $name = (string) ($user['display_name'] ?? 'A player');
        $inRoom = Db::all('SELECT user_id FROM room_players WHERE room_id = ?', [$roomId]);
        $skip = array_map(static fn (array $r): int => (int) $r['user_id'], $inRoom);
        $skip[] = $uid;
        Auth::ensureChallengesEnabledColumn();
        Auth::ensureChallengeGameColumns();
        $rows = Db::all(
            "SELECT u.id, u.challenges_enabled, u.challenge_pool, u.challenge_ludo, u.challenge_carrom
             FROM users u JOIN (" . self::ONLINE_SQL . ") t ON t.user_id = u.id
             WHERE t.la > DATE_SUB(NOW(), INTERVAL 3 MINUTE) AND u.banned = 0
             ORDER BY t.la DESC LIMIT 80",
            []
        );
        foreach ($rows as $row) {
            $tid = (int) $row['id'];
            if (in_array($tid, $skip, true)) {
                continue;
            }
            if (self::busy($tid) || !self::userAcceptsGame($row, $game)) {
                continue;
            }
            Db::run(
                'INSERT INTO challenges (from_user, to_user, game, level, stake, fee, room_id, expires_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))',
                [$uid, $tid, $game, $level, $stake, $fee, $roomId, self::OPEN_INVITE_SECONDS]
            );
            $id = Db::lastId();
            Push::notifyUser(
                $tid,
                'challenge',
                'Open table',
                $name . ' is waiting for a ' . strtoupper($game) . ' match.',
                ['game' => $game, 'roomId' => (string) $roomId],
                'challenge:' . $id
            );
        }
    }

    /** @var array<int,int> room id => last broadcast unix time */
    private static array $openBroadcastAt = [];

    /** Host still on matchmaking: refresh invites without spamming. */
    public static function maybeRebroadcastOpenMatch(array $user, array $roomView): void
    {
        $roomId = (int) ($roomView['id'] ?? 0);
        if ($roomId < 1 || (int) ($roomView['hostId'] ?? 0) !== (int) $user['id']) {
            return;
        }
        $now = time();
        if ((self::$openBroadcastAt[$roomId] ?? 0) + 45 > $now) {
            return;
        }
        self::$openBroadcastAt[$roomId] = $now;
        self::broadcastOpenMatch($user, $roomView);
    }

    public static function cancelPendingForRoom(int $roomId): void
    {
        if ($roomId < 1) {
            return;
        }
        Db::run("UPDATE challenges SET status = 'cancelled' WHERE room_id = ? AND status = 'pending'", [$roomId]);
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
        $openRoomId = $c['room_id'] === null ? null : (int) $c['room_id'];
        try {
            if ($openRoomId !== null && $openRoomId > 0) {
                $room = RoomService::joinOpenChallenge($openRoomId, $user);
            } else {
                $room = RoomService::matchUp($host, $user, $c['game'], $c['level'] === null ? null : (int) $c['level']);
            }
        } catch (\Throwable $e) {
            Db::run("UPDATE challenges SET status = 'pending' WHERE id = ? AND status = 'accepted' AND room_id IS NULL", [$id]);
            throw $e;
        }
        Db::run('UPDATE challenges SET room_id = ? WHERE id = ?', [$room['id'], $id]);
        if (($room['status'] ?? '') !== 'waiting') {
            self::cancelPendingForRoom((int) $room['id']);
        }
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

    private static function challengePrize(string $game, int $stake): int
    {
        if ($stake <= 0) {
            return 0;
        }
        $seats = RoomService::GAMES[$game] ?? 2;
        return Economy::winnerPrize($stake, $seats);
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
            'prize' => self::challengePrize((string) $c['game'], (int) $c['stake']),
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
