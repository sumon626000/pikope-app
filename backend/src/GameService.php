<?php
declare(strict_types=1);

namespace App;

use App\Game\Bots;
use App\Game\CarromEngine;
use App\Game\CarromPhysics;
use App\Game\Physics;
use App\Game\LudoEngine;
use App\Game\PokerEngine;
use App\Game\PoolEngine;

/** Loads, mutates and stores matches. Every change happens under a row lock. */
final class GameService
{
    public const WIN_XP = 60;
    public const PLAY_XP = 20;

    public static function nowMs(): int
    {
        return (int) floor(microtime(true) * 1000);
    }

    /** @param list<array{uid:int,name:string,avatar:string,bot?:bool}> $players */
    public static function create(int $roomId, string $game, array $players, int $shotSeconds, array $meta = []): int
    {
        $isLudo = str_starts_with($game, 'ludo');
        $state = match (true) {
            $game === 'poker' => PokerEngine::newState($players, $shotSeconds, self::nowMs()),
            $isLudo => LudoEngine::newState(count($players), $players, $shotSeconds, self::nowMs()),
            $game === 'carrom' => CarromEngine::newState($players, $shotSeconds, self::nowMs()),
            default => PoolEngine::newState($game, $players, $shotSeconds, self::nowMs()),
        };
        // Stake, prize and (poker) the jackpot draw travel with the match.
        $state['bet'] = $meta + ['mode' => 'friendly', 'level' => null, 'stake' => 0, 'prize' => 0, 'multiplier' => null];
        // Seats played by the server's stand-in players (see Game\Bots).
        $state['bots'] = array_keys(array_filter($players, static fn (array $p): bool => !empty($p['bot'])));
        $state['lastActMs'] = self::nowMs();
        Db::run('INSERT INTO games (room_id, game, state, has_bots) VALUES (?, ?, ?, ?)',
            [$roomId, $game, json_encode($state), $state['bots'] === [] ? 0 : 1]);
        $gameId = Db::lastId();
        foreach ($players as $seat => $p) {
            Db::run('INSERT INTO game_players (game_id, user_id, seat) VALUES (?, ?, ?)', [$gameId, $p['uid'], $seat]);
        }
        return $gameId;
    }

    private static function seatOf(int $gameId, int $uid): int
    {
        $row = Db::one('SELECT seat FROM game_players WHERE game_id = ? AND user_id = ?', [$gameId, $uid]);
        if ($row === null) {
            throw ApiError::forbidden('You are not in this game');
        }
        return (int) $row['seat'];
    }

    /** @param array<string,mixed> $state */
    private static function view(int $gameId, int $version, array $state, int $seat): array
    {
        // Server bookkeeping, not for players (which seats are bots stays private).
        unset($state['bots'], $state['lastActMs']);
        return [
            'id' => $gameId,
            'version' => $version,
            'serverNow' => self::nowMs(),
            'state' => match ($state['kind']) {
                'poker' => PokerEngine::view($state, $seat),
                'ludo' => LudoEngine::view($state, $seat),
                'carrom' => CarromEngine::view($state, $seat),
                default => PoolEngine::view($state, $seat),
            },
        ];
    }

    /** @param array<string,mixed> $state */
    private static function tick(array &$state): bool
    {
        return match ($state['kind']) {
            'poker' => PokerEngine::tick($state, self::nowMs()),
            'ludo' => LudoEngine::tick($state, self::nowMs()),
            'carrom' => CarromEngine::tick($state, self::nowMs()),
            default => PoolEngine::tick($state, self::nowMs()),
        };
    }

    /** Poll. Overdue shot clocks are enforced here, whoever happens to ask. */
    public static function get(int $gameId, int $uid, int $since): array
    {
        self::ensureAimColumn();
        $seat = self::seatOf($gameId, $uid);
        $row = Db::one('SELECT version, status, state, aim FROM games WHERE id = ?', [$gameId]);
        if ($row === null) {
            throw ApiError::notFound('Game not found');
        }
        $state = json_decode($row['state'], true);
        if ($row['status'] === 'active' && self::nowMs() > $state['deadline'] + 1500) {
            return self::withAim(self::mutate($gameId, $seat, static fn (array &$s): bool => false), $gameId);
        }
        if ((int) $row['version'] <= $since) {
            return self::withAim([
                'id' => $gameId,
                'version' => (int) $row['version'],
                'serverNow' => self::nowMs(),
                'unchanged' => true,
            ], $gameId, $row['aim']);
        }
        return self::withAim(self::view($gameId, (int) $row['version'], $state, $seat), $gameId, $row['aim']);
    }

    /**
     * Where the player on turn is pointing the cue. Not part of the rules:
     * stored so phones that only poll HTTP can still watch the lineup.
     * @param array<string,mixed> $body
     * @return array{ok:bool}
     */
    public static function shareAim(int $gameId, int $uid, array $body): array
    {
        self::ensureAimColumn();
        $seat = self::seatOf($gameId, $uid);
        $row = Db::one('SELECT status, state FROM games WHERE id = ?', [$gameId]);
        if ($row === null || $row['status'] !== 'active') {
            return ['ok' => true];
        }
        $state = json_decode($row['state'], true);
        $turn = (int) ($state['turn'] ?? $state['currentIndex'] ?? -1);
        $phase = (string) ($state['phase'] ?? '');
        if ($turn !== $seat || !in_array($phase, ['playerTurn', 'pushOutChoice', 'declarePhase'], true)) {
            return ['ok' => true];
        }
        $aim = ['s' => $seat];
        foreach (['a', 'p', 'x', 'y'] as $key) {
            if (!isset($body[$key]) || !is_numeric($body[$key])) {
                continue;
            }
            $value = (float) $body[$key];
            if (!is_finite($value)) {
                continue;
            }
            $aim[$key] = round($value, 4);
        }
        if (!isset($aim['a']) && !isset($aim['x'])) {
            return ['ok' => true];
        }
        Db::run('UPDATE games SET aim = ? WHERE id = ?', [json_encode($aim), $gameId]);
        return ['ok' => true];
    }

    private static bool $aimReady = false;

    private static function ensureAimColumn(): void
    {
        if (self::$aimReady) {
            return;
        }
        $have = Db::pdo()->query("SHOW COLUMNS FROM games LIKE 'aim'")->fetch();
        if (!$have) {
            try {
                Db::pdo()->exec('ALTER TABLE games ADD COLUMN aim TEXT NULL');
            } catch (\Throwable $e) {
                // A parallel request added the column first.
            }
        }
        self::$aimReady = true;
    }

    /**
     * @param array<string,mixed> $view
     * @param mixed $aimJson false = read it; null = none stored
     */
    private static function withAim(array $view, int $gameId, mixed $aimJson = false): array
    {
        if ($aimJson === false) {
            $row = Db::one('SELECT aim FROM games WHERE id = ?', [$gameId]);
            $aimJson = $row['aim'] ?? null;
        }
        if (is_string($aimJson) && $aimJson !== '') {
            $aim = json_decode($aimJson, true);
            if (is_array($aim)) {
                $view['aim'] = $aim;
            }
        }
        return $view;
    }

    /**
     * Locks the game, applies overdue timeouts, then $fn; stores the result.
     * @param callable(array<string,mixed>&):bool $fn returns whether it changed the state
     */
    private static function mutate(int $gameId, int $seat, callable $fn): array
    {
        self::ensureAimColumn();
        return Db::transaction(static function () use ($gameId, $seat, $fn): array {
            $row = Db::one('SELECT version, status, state, room_id, game FROM games WHERE id = ? FOR UPDATE', [$gameId]);
            if ($row === null) {
                throw ApiError::notFound('Game not found');
            }
            $state = json_decode($row['state'], true);
            $version = (int) $row['version'];
            if ($row['status'] !== 'active') {
                return self::view($gameId, $version, $state, $seat);
            }
            $changed = self::tick($state);
            $changed = $fn($state) || $changed;
            if ($changed) {
                $version++;
                $state['lastActMs'] = self::nowMs();
                Db::run('UPDATE games SET state = ?, version = ?, aim = NULL WHERE id = ?', [json_encode($state), $version, $gameId]);
                if ($state['phase'] === 'gameOver') {
                    self::finish($gameId, (int) $row['room_id'], $row['game'], $state);
                }
            }
            return self::view($gameId, $version, $state, $seat);
        });
    }

    /** Books the result: prize, win/game counters, experience, history. @param array<string,mixed> $state */
    private static function finish(int $gameId, int $roomId, string $game, array $state): void
    {
        $winnerUid = (int) $state['players'][$state['winner']]['uid'];
        // Pay at most once — ignore duplicate gameOver ticks or concurrent finish attempts.
        $done = Db::run(
            "UPDATE games SET status = 'finished', winner_id = ?, finished_at = NOW() WHERE id = ? AND status = 'active'",
            [$winnerUid, $gameId]
        );
        if ($done->rowCount() === 0) {
            return;
        }
        Db::run("UPDATE rooms SET status = 'closed' WHERE id = ?", [$roomId]);
        $bet = $state['bet'] ?? ['stake' => 0, 'prize' => 0];
        $room = Db::one('SELECT fee FROM rooms WHERE id = ?', [$roomId]);
        $buyIn = (int) $bet['stake'] + ((int) $bet['stake'] > 0 ? (int) $room['fee'] : 0);
        foreach ($state['players'] as $p) {
            $won = (int) $p['uid'] === $winnerUid;
            $prize = $won ? Promotions::prizeWithBonus((int) $bet['prize']) : 0;
            if ($prize > 0) {
                Economy::move((int) $p['uid'], $prize, 'prize', $roomId);
            }
            Db::run('UPDATE users SET games = games + 1, wins = wins + ?, xp = xp + ? WHERE id = ?',
                [$won ? 1 : 0, $won ? self::WIN_XP : self::PLAY_XP, $p['uid']]);
            Db::run("INSERT INTO match_results (game_id, user_id, game, mode, won, coins_delta, stake, prize) VALUES (?, ?, ?, 'online', ?, ?, ?, ?)",
                [$gameId, $p['uid'], $game, $won ? 1 : 0, $prize - $buyIn, $bet['stake'], $prize]);
        }
    }

    /**
     * The match this user is still part of, if any - so an app that was
     * closed or lost its connection can get back to the table.
     * @return array<string,mixed>|null
     */
    public static function activeFor(int $uid): ?array
    {
        $row = Db::one(
            "SELECT g.id, g.room_id, g.game, g.state, p.seat FROM games g
             JOIN game_players p ON p.game_id = g.id
             WHERE p.user_id = ? AND g.status = 'active' ORDER BY g.id DESC LIMIT 1",
            [$uid]
        );
        if ($row === null) {
            return null;
        }
        $state = json_decode($row['state'], true);
        $seat = (int) $row['seat'];
        if ($state['phase'] === 'gameOver' || ($state['players'][$seat]['out'] ?? false)) {
            return null;
        }
        return [
            'gameId' => (int) $row['id'],
            'roomId' => (int) $row['room_id'],
            'game' => $row['game'],
            'seat' => $seat,
            'shotSeconds' => (int) $state['shotSeconds'],
            'players' => array_map(static fn (array $p): array => ['name' => $p['name'], 'avatar' => $p['avatar'], 'cue' => $p['cue'] ?? 'classic'], $state['players']),
            'bet' => $state['bet'] ?? null,
        ];
    }

    /**
     * Housekeeping (cron): rules on every match whose clock ran out while no
     * player was polling, until each is up to date or finished.
     */
    public static function sweep(): int
    {
        $touched = 0;
        $rows = Db::all("SELECT id FROM games WHERE status = 'active'");
        foreach ($rows as $row) {
            for ($i = 0; $i < 40; $i++) {
                $state = json_decode(Db::one('SELECT state FROM games WHERE id = ?', [$row['id']])['state'], true);
                if ($state['phase'] === 'gameOver' || self::nowMs() <= $state['deadline'] + 1500) {
                    break;
                }
                self::mutate((int) $row['id'], 0, static fn (array &$s): bool => false);
                $touched++;
            }
        }
        return $touched;
    }

    // ------------------------------------------------------------ actions

    private static function num(array $body, string $key, float $min, float $max): float
    {
        $v = $body[$key] ?? null;
        if (!is_int($v) && !is_float($v) || !is_finite((float) $v)) {
            throw ApiError::badRequest("'$key' must be a number");
        }
        return max($min, min($max, (float) $v));
    }

    private static function int(array $body, string $key): int
    {
        $v = $body[$key] ?? null;
        if (!is_int($v)) {
            throw ApiError::badRequest("'$key' must be an integer");
        }
        return $v;
    }

    /** @return list<int> */
    private static function ballList(mixed $v): array
    {
        if (!is_array($v)) {
            throw ApiError::badRequest('Ball list expected');
        }
        $out = [];
        foreach ($v as $b) {
            if (is_int($b) && $b >= 1 && $b <= 15 && !in_array($b, $out, true)) {
                $out[] = $b;
            }
        }
        return $out;
    }

    /**
     * Plays a shot: the server places the cue ball, simulates the stroke,
     * rules on what happened and stores where every ball came to rest.
     * @param array<string,mixed> $s @param array<string,mixed> $body
     */
    private static function playShot(array &$s, int $seat, array $body, int $now): void
    {
        $poker = $s['kind'] === 'poker';
        $dirX = self::num($body, 'dirX', -1.0, 1.0);
        $dirY = self::num($body, 'dirY', -1.0, 1.0);
        if (abs(sqrt($dirX * $dirX + $dirY * $dirY) - 1.0) > 1e-6) {
            throw ApiError::badRequest('Aim direction must be a unit vector', 'bad_aim');
        }
        $power = self::num($body, 'power', 0.0, 1.0);
        $spinX = self::num($body, 'spinX', -1.0, 1.0);
        $spinY = self::num($body, 'spinY', -1.0, 1.0);

        // Turn and target checks first; nothing moves on a refused shot.
        $shot = ['dirX' => $dirX, 'dirY' => $dirY, 'power' => $power, 'spinX' => $spinX, 'spinY' => $spinY];
        if ($poker) {
            // What was revealed for this shot (the selection is cleared by the ruling).
            $shot['target'] = ['card' => $s['selectedCard'], 'freeBall' => $s['selectedFreeBall']];
        }
        $poker ? PokerEngine::shoot($s, $seat, $shot, $now) : PoolEngine::shoot($s, $seat, $shot, $now);

        $world = Physics::fromState($s['balls']);
        if ($s['ballInHand']) {
            $behind = $poker ? $s['isBreakShot'] : $s['behindHeadString'];
            $placed = $world->placeCue(self::num($body, 'cueX', -100.0, 1100.0), self::num($body, 'cueY', -100.0, 600.0), $behind);
            if (!$placed) {
                throw ApiError::conflict('The cue ball cannot go there', 'bad_cue');
            }
        }
        [$cueX, $cueY] = $world->cuePosition();
        $world->shoot($dirX, $dirY, $power, $spinX, $spinY);
        $seconds = $world->simulate();
        $outcome = $world->outcome();

        if ($poker) {
            PokerEngine::resolve($s, $seat, $outcome, $now);
            // Every ball may be somebody's objective: all of them come back.
            $respot = $outcome['pocketed'];
        } else {
            PoolEngine::resolve($s, $seat, $outcome, $now);
            $respot = $s['lastResult']['respot'];
        }
        foreach ($respot as $ball) {
            $world->respot($ball);
        }
        if ($outcome['cuePocketed']) {
            $world->respotCue();
        }
        $s['balls'] = $world->toState();
        $durationMs = (int) ceil($seconds * 1000);
        $s['lastShot'] = $shot + ['seq' => $s['shotSeq'], 'by' => $seat, 'cueX' => $cueX, 'cueY' => $cueY,
            'durationMs' => $durationMs, 'outcome' => $outcome];
        // The next shot clock starts once everyone has watched this shot.
        $s['deadline'] += $durationMs;
    }

    /**
     * Carrom: the server puts the striker on the shooter's base line where
     * they asked (nudged clear of pieces), simulates the stroke and rules on
     * it. The app replays the same stroke from the same numbers.
     * @param array<string,mixed> $s @param array<string,mixed> $body
     */
    private static function playCarromShot(array &$s, int $seat, array $body, int $now): void
    {
        $dirX = self::num($body, 'dirX', -1.0, 1.0);
        $dirY = self::num($body, 'dirY', -1.0, 1.0);
        if (abs(sqrt($dirX * $dirX + $dirY * $dirY) - 1.0) > 1e-6) {
            throw ApiError::badRequest('Aim direction must be a unit vector', 'bad_aim');
        }
        $power = self::num($body, 'power', 0.0, 1.0);
        $x = self::num($body, 'x', CarromPhysics::BASE_MIN_X, CarromPhysics::BASE_MAX_X);
        CarromEngine::shoot($s, $seat, $now);
        $world = CarromPhysics::fromState($s['discs']);
        $x = $world->placeStriker($seat, $x);
        $world->shoot($dirX, $dirY, $power);
        $seconds = $world->simulate();
        $outcome = ['pocketed' => $world->pocketed, 'strikerPocketed' => $world->strikerPocketed, 'firstContact' => $world->firstContact];
        CarromEngine::resolve($s, $world, $seat, $now);
        $s['discs'] = $world->toState();
        $durationMs = (int) ceil($seconds * 1000);
        $s['lastShot'] = ['seq' => $s['shotSeq'], 'by' => $seat, 'x' => $x, 'dirX' => $dirX, 'dirY' => $dirY,
            'power' => $power, 'durationMs' => $durationMs, 'outcome' => $outcome];
        // The next shot clock starts once everyone has watched this stroke.
        $s['deadline'] += $durationMs;
    }

    /**
     * Test hook (APP_TEST_HOOKS=1 only): rules on a scripted outcome without
     * simulating, so the rule paths can be driven deterministically.
     * @param array<string,mixed> $s @param array<string,mixed> $body
     */
    private static function scriptedShot(array &$s, int $seat, array $body, int $now): void
    {
        if (Config::get('APP_TEST_HOOKS', '0') !== '1') {
            throw ApiError::badRequest('Unknown action');
        }
        $poker = $s['kind'] === 'poker';
        $first = $body['firstContact'] ?? null;
        $outcome = [
            'firstContact' => is_int($first) && $first >= 1 && $first <= 15 ? $first : null,
            'pocketed' => self::ballList($body['pocketed'] ?? []),
            'cuePocketed' => (bool) ($body['cuePocketed'] ?? false),
            'railContact' => (bool) ($body['railContact'] ?? false),
            'railAfterContact' => (bool) ($body['railAfterContact'] ?? false),
            'objectBallsToRail' => (int) ($body['objectBallsToRail'] ?? 0),
            'pocketOf' => [],
        ];
        foreach ((array) ($body['pocketOf'] ?? []) as $ball => $pocket) {
            $outcome['pocketOf'][(int) $ball] = (int) $pocket;
        }
        $shot = ['dirX' => 1.0, 'dirY' => 0.0, 'power' => 0.5, 'spinX' => 0.0, 'spinY' => 0.0];
        if ($poker) {
            PokerEngine::shoot($s, $seat, $shot, $now);
            PokerEngine::resolve($s, $seat, $outcome, $now);
        } else {
            PoolEngine::shoot($s, $seat, $shot, $now);
            PoolEngine::resolve($s, $seat, $outcome, $now);
        }
    }

    /** @param array<string,mixed> $body */
    public static function act(int $gameId, int $uid, array $body): array
    {
        self::ensureAimColumn();
        $seat = self::seatOf($gameId, $uid);
        $type = (string) ($body['type'] ?? '');
        $now = self::nowMs();
        return self::mutate($gameId, $seat, static fn (array &$s): bool => self::apply($s, $seat, $uid, $gameId, $type, $body, $now));
    }

    /**
     * A server stand-in plays its turn if one is due: the decision (which may
     * test-run shots) is made outside the lock, then applied through the same
     * rules as a human's action - unless the match moved on meanwhile.
     */
    public static function driveBot(int $gameId): bool
    {
        $row = Db::one('SELECT status, state FROM games WHERE id = ?', [$gameId]);
        if ($row === null || $row['status'] !== 'active') {
            return false;
        }
        $state = json_decode($row['state'], true);
        $seat = Bots::due($state, self::nowMs());
        if ($seat === null) {
            return false;
        }
        $body = Bots::decide($state, $seat, self::nowMs());
        $stamp = $state['lastActMs'] ?? 0;
        $uid = (int) $state['players'][$seat]['uid'];
        $acted = false;
        self::mutate($gameId, $seat, static function (array &$s) use ($seat, $uid, $gameId, $body, $stamp, &$acted): bool {
            $now = self::nowMs();
            if (($s['lastActMs'] ?? 0) !== $stamp || Bots::due($s, $now) !== $seat) {
                return false;
            }
            // Work on a copy: a refused action must not leave half a change behind.
            $copy = $s;
            try {
                $acted = self::apply($copy, $seat, $uid, $gameId, (string) $body['type'], $body, $now);
            } catch (ApiError $e) {
                error_log("[bots] game $gameId seat $seat " . json_encode($body) . ' refused: ' . $e->getMessage());
                return false;
            }
            if ($acted) {
                $s = $copy;
            }
            return $acted;
        });
        return $acted;
    }

    /** Applies one player action to the locked state. @param array<string,mixed> $body */
    private static function apply(array &$s, int $seat, int $uid, int $gameId, string $type, array $body, int $now): bool
    {
        $poker = $s['kind'] === 'poker';
        $ludo = $s['kind'] === 'ludo';
        if ($ludo) {
            switch ($type) {
                case 'roll':
                    LudoEngine::roll($s, $seat, $now);
                    return true;
                case 'move':
                    LudoEngine::move($s, $seat, self::int($body, 'token'), $now);
                    return true;
                case 'leave':
                    LudoEngine::forfeit($s, $seat, $now);
                    return true;
            }
            throw ApiError::badRequest('Unknown action');
        }
        if ($s['kind'] === 'carrom') {
            switch ($type) {
                case 'shoot':
                    self::playCarromShot($s, $seat, $body, $now);
                    Db::run(
                        'INSERT INTO game_shots (game_id, seq, user_id, params, outcome, result) VALUES (?, ?, ?, ?, ?, ?)',
                        [$gameId, $s['lastShot']['seq'], $uid, json_encode(array_diff_key($s['lastShot'], ['outcome' => 1])),
                            json_encode($s['lastShot']['outcome']), json_encode($s['lastResult'])]
                    );
                    return true;
                case 'leave':
                    CarromEngine::forfeit($s, $seat, $now);
                    return true;
            }
            throw ApiError::badRequest('Unknown action');
        }
        switch ($type) {
            case 'shoot':
                self::playShot($s, $seat, $body, $now);
                Db::run(
                    'INSERT INTO game_shots (game_id, seq, user_id, params, outcome, result) VALUES (?, ?, ?, ?, ?, ?)',
                    [$gameId, $s['lastShot']['seq'], $uid, json_encode(array_diff_key($s['lastShot'], ['outcome' => 1])),
                        json_encode($s['lastShot']['outcome']), json_encode($s['lastResult'])]
                );
                return true;

            case 'test_shot':
                self::scriptedShot($s, $seat, $body, $now);
                return true;

            case 'leave':
                $poker ? PokerEngine::forfeit($s, $seat, $now) : PoolEngine::forfeit($s, $seat, $now);
                return true;
        }
        if ($poker) {
            switch ($type) {
                case 'pick_break':
                    PokerEngine::pickBreak($s, $seat, self::int($body, 'index'), $now);
                    return true;
                case 'select_card':
                    PokerEngine::selectCard($s, $seat, self::int($body, 'cardId'));
                    return true;
                case 'select_free':
                    PokerEngine::selectFreeBall($s, $seat, self::int($body, 'ball'));
                    return true;
                case 'declare':
                    PokerEngine::declareWinner($s, $seat);
                    return true;
            }
        } else {
            switch ($type) {
                case 'call_pocket':
                    PoolEngine::callPocket($s, $seat, self::int($body, 'pocket'));
                    return true;
                case 'push_out':
                    PoolEngine::togglePushOut($s, $seat);
                    return true;
                case 'push_out_answer':
                    PoolEngine::answerPushOut($s, $seat, (bool) ($body['shoot'] ?? true), $now);
                    return true;
            }
        }
        throw ApiError::badRequest('Unknown action');
    }
}
