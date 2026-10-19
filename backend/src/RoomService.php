<?php
declare(strict_types=1);

namespace App;

/** Lobbies: create, quick match, join by code, leave. A full room starts its game. */
final class RoomService
{
    /** 'billiard' is the staked 1v1 queue: 8-, 9- or 10-ball is drawn when the match starts. */
    public const GAMES = ['poker' => 4, 'eight' => 2, 'nine' => 2, 'ten' => 2, 'billiard' => 2, 'ludo2' => 2, 'ludo4' => 4, 'carrom' => 2];
    private const BILLIARD_GAMES = ['eight', 'nine', 'ten'];
    private const STALE_SECONDS = 20;

    private static function requireGame(string $game): int
    {
        if (!isset(self::GAMES[$game])) {
            throw ApiError::badRequest('Unknown game');
        }
        return self::GAMES[$game];
    }

    private static function newCode(): string
    {
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        do {
            $code = '';
            for ($i = 0; $i < 6; $i++) {
                $code .= $alphabet[random_int(0, strlen($alphabet) - 1)];
            }
        } while (Db::one('SELECT id FROM rooms WHERE code = ?', [$code]) !== null);
        return $code;
    }

    /** A player waits in one room at a time. */
    private static function leaveWaitingRooms(int $uid, ?int $except = null): void
    {
        $rows = Db::all(
            "SELECT r.id FROM rooms r JOIN room_players p ON p.room_id = r.id WHERE p.user_id = ? AND r.status = 'waiting'",
            [$uid]
        );
        foreach ($rows as $row) {
            if ((int) $row['id'] !== $except) {
                self::removeFromWaiting((int) $row['id'], $uid);
            }
        }
    }

    private static function removeFromWaiting(int $roomId, int $uid): void
    {
        Db::run('DELETE FROM room_players WHERE room_id = ? AND user_id = ?', [$roomId, $uid]);
        $next = Db::one('SELECT user_id FROM room_players WHERE room_id = ? ORDER BY seat LIMIT 1', [$roomId]);
        if ($next === null) {
            Db::run("UPDATE rooms SET status = 'closed' WHERE id = ?", [$roomId]);
        } else {
            Db::run('UPDATE rooms SET host_id = ? WHERE id = ? AND host_id = ?', [$next['user_id'], $roomId, $uid]);
        }
    }

    private static function pruneStale(int $roomId, int $keepUid): void
    {
        $stale = Db::all(
            'SELECT user_id FROM room_players WHERE room_id = ? AND user_id <> ? AND last_seen_at < DATE_SUB(NOW(), INTERVAL ? SECOND)',
            [$roomId, $keepUid, self::STALE_SECONDS]
        );
        foreach ($stale as $row) {
            self::removeFromWaiting($roomId, (int) $row['user_id']);
        }
    }

    public static function create(array $user, string $game, bool $private): array
    {
        self::requireGame($game);
        return Db::transaction(static function () use ($user, $game, $private): array {
            $uid = (int) $user['id'];
            self::leaveWaitingRooms($uid);
            Db::run('INSERT INTO rooms (code, game, host_id, is_private) VALUES (?, ?, ?, ?)',
                [self::newCode(), $game, $uid, $private ? 1 : 0]);
            $roomId = Db::lastId();
            Db::run('INSERT INTO room_players (room_id, user_id, seat) VALUES (?, ?, 0)', [$roomId, $uid]);
            return self::view($roomId);
        });
    }

    /**
     * Join any public room of this game that is waiting, or open a new one.
     * With a bet [$level] the room is a staked one ("billiard" or "poker")
     * and only players at that level meet; without, it is a free match.
     */
    public static function quick(array $user, string $game, ?int $level = null): array
    {
        $seats = self::requireGame($game);
        $bet = null;
        // Ludo, carrom and billiard share the same stake ladder; poker has its own.
        $stakeMode = $game === 'poker' ? 'poker' : 'billiard';
        $needsLevel = $game === 'billiard' || $game === 'carrom' || str_starts_with($game, 'ludo');
        if ($level !== null) {
            if ($game !== 'poker' && !$needsLevel && !in_array($game, self::BILLIARD_GAMES, true)) {
                throw ApiError::badRequest('This game has no bet levels');
            }
            $bet = Economy::level($stakeMode, $level);
            if ((int) $user['coins'] < $bet['buyIn']) {
                throw ApiError::conflict('Not enough coins for this table', 'not_enough_coins');
            }
        } elseif ($needsLevel) {
            throw ApiError::badRequest('Pick a bet level');
        }
        return Db::transaction(static function () use ($user, $game, $seats, $level, $bet): array {
            $uid = (int) $user['id'];
            $candidates = Db::all(
                "SELECT id FROM rooms WHERE status = 'waiting' AND is_private = 0 AND game = ? AND level <=> ?
                 ORDER BY id LIMIT 10 FOR UPDATE",
                [$game, $level]
            );
            foreach ($candidates as $row) {
                $roomId = (int) $row['id'];
                self::pruneStale($roomId, $uid);
                $room = Db::one('SELECT status FROM rooms WHERE id = ?', [$roomId]);
                $count = (int) Db::one('SELECT COUNT(*) AS n FROM room_players WHERE room_id = ?', [$roomId])['n'];
                $mine = Db::one('SELECT 1 FROM room_players WHERE room_id = ? AND user_id = ?', [$roomId, $uid]) !== null;
                if ($room['status'] === 'waiting' && ($mine || $count < $seats)) {
                    self::leaveWaitingRooms($uid, $roomId);
                    return self::seat($roomId, $user);
                }
            }
            self::leaveWaitingRooms($uid);
            Db::run('INSERT INTO rooms (code, game, host_id, is_private, level, stake, fee) VALUES (?, ?, ?, 0, ?, ?, ?)',
                [self::newCode(), $game, $uid, $level, $bet['stake'] ?? 0, $bet['fee'] ?? 0]);
            $roomId = Db::lastId();
            Db::run('INSERT INTO room_players (room_id, user_id, seat) VALUES (?, ?, 0)', [$roomId, $uid]);
            return self::view($roomId);
        });
    }

    public static function join(array $user, string $code): array
    {
        return Db::transaction(static function () use ($user, $code): array {
            $room = Db::one('SELECT id, status FROM rooms WHERE code = ? FOR UPDATE', [strtoupper($code)]);
            if ($room === null) {
                throw ApiError::notFound('No room with that code');
            }
            $roomId = (int) $room['id'];
            $mine = Db::one('SELECT 1 FROM room_players WHERE room_id = ? AND user_id = ?', [$roomId, $user['id']]) !== null;
            if ($room['status'] !== 'waiting' && !$mine) {
                throw ApiError::conflict('That room has already started', 'room_started');
            }
            if ($room['status'] !== 'waiting') {
                return self::view($roomId);
            }
            self::pruneStale($roomId, (int) $user['id']);
            self::leaveWaitingRooms((int) $user['id'], $roomId);
            return self::seat($roomId, $user);
        });
    }

    /** Seats the user (room row is locked by the caller) and starts the game when full. */
    /**
     * Seats two named players in a fresh private room and starts the match
     * (used by Challenge accept). Both must afford the buy-in. Returns the
     * room view (with gameId once started).
     * @param array<string,mixed> $host @param array<string,mixed> $guest
     */
    public static function matchUp(array $host, array $guest, string $game, ?int $level): array
    {
        $seats = self::requireGame($game);
        if ($seats !== 2) {
            throw ApiError::badRequest('Challenges are 1 v 1 only');
        }
        $bet = $level === null ? ['stake' => 0, 'fee' => 0, 'buyIn' => 0] : Economy::level($game === 'poker' ? 'poker' : 'billiard', $level);
        return Db::transaction(static function () use ($host, $guest, $game, $level, $bet): array {
            foreach ([$host, $guest] as $u) {
                $coins = (int) Db::one('SELECT coins FROM users WHERE id = ? FOR UPDATE', [$u['id']])['coins'];
                if ($coins < ($bet['buyIn'] ?? 0)) {
                    throw ApiError::conflict('A player cannot afford this stake', 'not_enough_coins');
                }
            }
            self::leaveWaitingRooms((int) $host['id']);
            self::leaveWaitingRooms((int) $guest['id']);
            Db::run('INSERT INTO rooms (code, game, host_id, is_private, level, stake, fee) VALUES (?, ?, ?, 1, ?, ?, ?)',
                [self::newCode(), $game, $host['id'], $level, $bet['stake'] ?? 0, $bet['fee'] ?? 0]);
            $roomId = Db::lastId();
            Db::run('INSERT INTO room_players (room_id, user_id, seat) VALUES (?, ?, 0)', [$roomId, $host['id']]);
            // Seating the second player fills the room and starts the game.
            return self::seat($roomId, $guest);
        });
    }

    private static function seat(int $roomId, array $user): array
    {
        $room = Db::one('SELECT game, shot_seconds, level, stake, fee FROM rooms WHERE id = ?', [$roomId]);
        $needed = self::GAMES[$room['game']];
        $players = Db::all('SELECT user_id, seat FROM room_players WHERE room_id = ? ORDER BY seat', [$roomId]);
        $taken = array_map(static fn ($p) => (int) $p['seat'], $players);
        $mine = in_array((int) $user['id'], array_map(static fn ($p) => (int) $p['user_id'], $players), true);
        if (!$mine) {
            if (count($players) >= $needed) {
                throw ApiError::conflict('That room is full', 'room_full');
            }
            $seat = 0;
            while (in_array($seat, $taken, true)) {
                $seat++;
            }
            Db::run('INSERT INTO room_players (room_id, user_id, seat) VALUES (?, ?, ?)', [$roomId, $user['id'], $seat]);
        } else {
            Db::run('UPDATE room_players SET last_seen_at = NOW() WHERE room_id = ? AND user_id = ?', [$roomId, $user['id']]);
        }
        $seated = Db::all(
            'SELECT u.id, u.display_name, u.avatar, u.cue, u.is_bot FROM room_players p JOIN users u ON u.id = p.user_id
             WHERE p.room_id = ? ORDER BY p.seat',
            [$roomId]
        );
        if (count($seated) === $needed) {
            self::start($roomId, $room, $seated);
        }
        return self::view($roomId);
    }

    /**
     * Every seat is taken: collect the buy-ins and begin. A player who can
     * no longer pay loses the seat and the room keeps waiting.
     * @param array<string,mixed> $room @param list<array<string,mixed>> $seated
     */
    private static function start(int $roomId, array $room, array $seated): void
    {
        $stake = (int) $room['stake'];
        $buyIn = $stake + (int) $room['fee'];
        $game = $room['game'];
        $meta = ['mode' => $game === 'poker' ? 'poker' : (str_starts_with($game, 'ludo') ? 'ludo' : (in_array($game, ['billiard', 'carrom'], true) ? $game : 'friendly')),
            'level' => $room['level'] === null ? null : (int) $room['level'], 'stake' => $stake, 'prize' => 0, 'multiplier' => null];
        if ($stake > 0) {
            $short = false;
            foreach ($seated as $u) {
                $coins = (int) Db::one('SELECT coins FROM users WHERE id = ? FOR UPDATE', [$u['id']])['coins'];
                if ($coins < $buyIn) {
                    self::removeFromWaiting($roomId, (int) $u['id']);
                    $short = true;
                }
            }
            if ($short) {
                return;
            }
            foreach ($seated as $u) {
                Economy::move((int) $u['id'], -$buyIn, 'buy_in', $roomId);
                if ((int) ($u['is_bot'] ?? 0) !== 1) {
                    Economy::payReferral((int) $u['id'], $stake, $roomId);
                }
            }
            if ($game === 'poker') {
                $meta['multiplier'] = Economy::drawMultiplier();
                $meta['prize'] = $stake * $meta['multiplier'];
                // What the wheel shows around the winning slice.
                $meta['wheel'] = array_map(static fn (int $x): int => $x * $stake, array_column(Economy::config()['jackpot'], 'x'));
            } else {
                $meta['prize'] = Economy::winnerPrize($stake, count($seated));
            }
        }
        if ($game === 'billiard') {
            $game = self::BILLIARD_GAMES[random_int(0, count(self::BILLIARD_GAMES) - 1)];
        }
        $gameId = GameService::create($roomId, $game, array_map(static fn ($u) => [
            'uid' => (int) $u['id'], 'name' => $u['display_name'], 'avatar' => $u['avatar'], 'cue' => $u['cue'],
            'bot' => (bool) ($u['is_bot'] ?? false),
        ], $seated), (int) $room['shot_seconds'], $meta);
        Db::run("UPDATE rooms SET status = 'playing', game = ?, game_id = ?, prize = ?, multiplier = ? WHERE id = ?",
            [$game, $gameId, $meta['prize'], $meta['multiplier'], $roomId]);
    }

    /**
     * Nobody else came: bots take the empty seats of a public room and the
     * match starts. Only while every person seated is still on the waiting
     * screen (polled in the last few seconds), so nobody is charged a buy-in
     * for a match they already walked away from.
     */
    public static function fillWithBots(int $roomId): bool
    {
        return Db::transaction(static function () use ($roomId): bool {
            $room = Db::one('SELECT * FROM rooms WHERE id = ? FOR UPDATE', [$roomId]);
            if ($room === null || $room['status'] !== 'waiting' || (int) $room['is_private'] === 1) {
                return false;
            }
            $players = Db::all(
                'SELECT p.user_id, u.is_bot,
                        TIMESTAMPDIFF(SECOND, p.joined_at, NOW()) AS waited,
                        TIMESTAMPDIFF(SECOND, p.last_seen_at, NOW()) AS idle
                 FROM room_players p JOIN users u ON u.id = p.user_id WHERE p.room_id = ?',
                [$roomId]
            );
            $humans = array_values(array_filter($players, static fn (array $p): bool => !(int) $p['is_bot']));
            if ($humans === [] || max(array_map(static fn (array $p): int => (int) $p['waited'], $humans)) < BotService::fillSeconds()) {
                return false;
            }
            foreach ($humans as $h) {
                if ((int) $h['idle'] > 6) {
                    return false;
                }
            }
            $missing = self::GAMES[$room['game']] - count($players);
            if ($missing <= 0) {
                return false;
            }
            $bots = BotService::pick($missing, (int) $room['stake'] + (int) $room['fee'], array_map(static fn (array $p): int => (int) $p['user_id'], $players));
            foreach ($bots as $bot) {
                self::seat($roomId, $bot);
            }
            return Db::one('SELECT status FROM rooms WHERE id = ?', [$roomId])['status'] === 'playing';
        });
    }

    /** Poll: also the heartbeat that keeps the caller's seat. */
    public static function get(int $roomId, array $user): array
    {
        $uid = (int) $user['id'];
        return Db::transaction(static function () use ($roomId, $uid): array {
            $room = Db::one('SELECT status FROM rooms WHERE id = ? FOR UPDATE', [$roomId]);
            if ($room === null) {
                throw ApiError::notFound('Room not found');
            }
            if (Db::one('SELECT 1 FROM room_players WHERE room_id = ? AND user_id = ?', [$roomId, $uid]) === null) {
                throw ApiError::forbidden('You are not in this room');
            }
            Db::run('UPDATE room_players SET last_seen_at = NOW() WHERE room_id = ? AND user_id = ?', [$roomId, $uid]);
            if ($room['status'] === 'waiting') {
                self::pruneStale($roomId, $uid);
            }
            return self::view($roomId);
        });
    }

    public static function leave(int $roomId, array $user): array
    {
        $uid = (int) $user['id'];
        $room = Db::one('SELECT status, game_id FROM rooms WHERE id = ?', [$roomId]);
        if ($room === null) {
            throw ApiError::notFound('Room not found');
        }
        if ($room['status'] === 'waiting') {
            Db::transaction(static function () use ($roomId, $uid): void {
                Db::one('SELECT id FROM rooms WHERE id = ? FOR UPDATE', [$roomId]);
                self::removeFromWaiting($roomId, $uid);
            });
        } elseif ($room['status'] === 'playing' && $room['game_id'] !== null) {
            GameService::act((int) $room['game_id'], $uid, ['type' => 'leave']);
        }
        return ['ok' => true];
    }

    /**
     * Play again with the same people: the first player to ask opens a new
     * private room, the others are seated in it as they ask.
     */
    public static function rematch(int $roomId, array $user): array
    {
        return Db::transaction(static function () use ($roomId, $user): array {
            $uid = (int) $user['id'];
            $room = Db::one('SELECT game, status, next_room_id, is_private, level, stake, fee FROM rooms WHERE id = ? FOR UPDATE', [$roomId]);
            if ($room === null) {
                throw ApiError::notFound('Room not found');
            }
            if (Db::one('SELECT 1 FROM room_players WHERE room_id = ? AND user_id = ?', [$roomId, $uid]) === null) {
                throw ApiError::forbidden('You were not in this room');
            }
            if ($room['status'] !== 'closed') {
                throw ApiError::conflict('That match is not over yet', 'not_finished');
            }
            self::leaveWaitingRooms($uid, $room['next_room_id'] === null ? null : (int) $room['next_room_id']);
            $next = $room['next_room_id'] === null ? null
                : Db::one('SELECT id, status FROM rooms WHERE id = ? FOR UPDATE', [$room['next_room_id']]);
            $mine = $next !== null
                && Db::one('SELECT 1 FROM room_players WHERE room_id = ? AND user_id = ?', [$next['id'], $uid]) !== null;
            if ($next !== null && ($next['status'] === 'waiting' || $mine)) {
                return $next['status'] === 'waiting' ? self::seat((int) $next['id'], $user) : self::view((int) $next['id']);
            }
            // A match against stand-ins: play again at the same table (public,
            // same stake) so bots can sit down again if nobody else does.
            $vsBots = Db::one('SELECT 1 FROM room_players p JOIN users u ON u.id = p.user_id WHERE p.room_id = ? AND u.is_bot = 1', [$roomId]) !== null;
            if ($vsBots) {
                $stake = (int) $room['stake'] + (int) $room['fee'];
                if ($stake > 0 && (int) Db::one('SELECT coins FROM users WHERE id = ?', [$uid])['coins'] < $stake) {
                    throw ApiError::conflict('Not enough coins for this table', 'not_enough_coins');
                }
                $game = $room['game'];
                if (in_array($game, self::BILLIARD_GAMES, true) && $room['level'] !== null) {
                    $game = 'billiard';
                }
                Db::run('INSERT INTO rooms (code, game, host_id, is_private, level, stake, fee) VALUES (?, ?, ?, 0, ?, ?, ?)',
                    [self::newCode(), $game, $uid, $room['level'], $room['stake'], $room['fee']]);
            } else {
                Db::run('INSERT INTO rooms (code, game, host_id, is_private) VALUES (?, ?, ?, 1)', [self::newCode(), $room['game'], $uid]);
            }
            $newId = Db::lastId();
            Db::run('INSERT INTO room_players (room_id, user_id, seat) VALUES (?, ?, 0)', [$newId, $uid]);
            Db::run('UPDATE rooms SET next_room_id = ? WHERE id = ?', [$newId, $roomId]);
            return self::view($newId);
        });
    }

    private static function view(int $roomId): array
    {
        $room = Db::one('SELECT * FROM rooms WHERE id = ?', [$roomId]);
        $players = Db::all(
            'SELECT u.id, u.display_name, u.avatar, u.cue, p.seat FROM room_players p JOIN users u ON u.id = p.user_id
             WHERE p.room_id = ? ORDER BY p.seat',
            [$roomId]
        );
        return [
            'id' => (int) $room['id'],
            'code' => $room['code'],
            'game' => $room['game'],
            'status' => $room['status'],
            'isPrivate' => (bool) $room['is_private'],
            'hostId' => (int) $room['host_id'],
            'gameId' => $room['game_id'] === null ? null : (int) $room['game_id'],
            'seats' => self::GAMES[$room['game']],
            'shotSeconds' => (int) $room['shot_seconds'],
            'level' => $room['level'] === null ? null : (int) $room['level'],
            'stake' => (int) $room['stake'],
            'buyIn' => (int) $room['stake'] + (int) $room['fee'],
            'prize' => (int) $room['prize'],
            'multiplier' => $room['multiplier'] === null ? null : (int) $room['multiplier'],
            'players' => array_map(static fn ($p) => [
                'id' => (int) $p['id'], 'name' => $p['display_name'], 'avatar' => $p['avatar'], 'cue' => $p['cue'],
                'seat' => (int) $p['seat'],
            ], $players),
        ];
    }
}
