<?php
declare(strict_types=1);

// Stand-in players end to end, against a running server and bot worker:
//   BOT_FILL_SECONDS=2 BOT_SPEED=6 php bin/bot-worker.php --seconds=900 &
//   php tests/bot_flow.php http://127.0.0.1:8080
// A lone guest quick-matches Ludo (staked), carrom (staked), nine-ball and Billiard Poker
// (staked); nobody else joins, bots take the seats and play every match out.

require dirname(__DIR__) . '/src/bootstrap.php';

use App\Game\PokerEngine;

$base = rtrim($argv[1] ?? 'http://127.0.0.1:8080', '/');
$passed = 0;

function call(string $method, string $path, ?string $token = null, ?array $body = null): array
{
    global $base;
    $ch = curl_init($base . $path);
    $headers = ['Content-Type: application/json'];
    if ($token !== null) {
        $headers[] = "Authorization: Bearer $token";
    }
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true, CURLOPT_HTTPHEADER => $headers,
        CURLOPT_POSTFIELDS => $body === null ? null : json_encode($body),
    ]);
    $raw = curl_exec($ch);
    return [curl_getinfo($ch, CURLINFO_HTTP_CODE), json_decode((string) $raw, true) ?? ['raw' => $raw]];
}

function check(bool $ok, string $what): void
{
    global $passed;
    if (!$ok) {
        fwrite(STDERR, "FAIL: $what\n");
        exit(1);
    }
    $passed++;
}

function coins(string $token): int
{
    return (int) call('GET', '/me', $token)[1]['user']['coins'];
}

/** Quick match, then wait on the "searching" screen until bots fill the room. */
function matchWithBots(string $token, string $game, ?int $level): array
{
    [$st, $room] = call('POST', '/rooms/quick', $token, ['game' => $game, 'level' => $level]);
    check($st === 200 && $room['status'] === 'waiting', "$game: waiting for an opponent");
    $t0 = microtime(true);
    while ($room['status'] === 'waiting' && microtime(true) - $t0 < 30) {
        usleep(500000);
        $room = call('GET', "/rooms/{$room['id']}", $token)[1];
    }
    check($room['status'] === 'playing' && $room['gameId'] !== null, "$game: bots filled the room");
    check(count($room['players']) === $room['seats'], "$game: every seat taken");
    printf("  %s: started after %.1fs vs %s\n", $game, microtime(true) - $t0,
        implode(', ', array_map(static fn ($p) => $p['name'], array_slice($room['players'], 1))));
    return $room;
}

function view(string $token, int $gameId): array
{
    [$st, $r] = call('GET', "/games/$gameId?since=0", $token);
    check($st === 200, 'poll game');
    return $r['state'];
}

/** Straight shot from the cue ball at ball $b; ball in hand goes somewhere free. */
function aimAt(array $s, int $b, bool $behind): array
{
    $balls = $s['balls'];
    [$cx, $cy] = [$balls[0][0], $balls[0][1]];
    if ($s['ballInHand']) {
        foreach ([[200, 250], [150, 120], [150, 380], [230, 60], [230, 440]] as [$x, $y]) {
            $ok = true;
            for ($i = 1; $i < 16; $i++) {
                if (!$balls[$i][2] && hypot($balls[$i][0] - $x, $balls[$i][1] - $y) < 40) {
                    $ok = false;
                }
            }
            if ($ok && (!$behind || $x <= 250)) {
                [$cx, $cy] = [$x, $y];
                break;
            }
        }
    }
    $a = atan2($balls[$b][1] - $cy, $balls[$b][0] - $cx);
    return ['type' => 'shoot', 'dirX' => cos($a), 'dirY' => sin($a), 'power' => 0.55, 'spinX' => 0, 'spinY' => 0, 'cueX' => $cx, 'cueY' => $cy];
}

/** Carrom: a straight, medium stroke from the middle of the base line at the nearest own piece. */
function carromShot(array $s, int $me): array
{
    $colour = $s['players'][$me]['colour'];
    $sy = $me === 0 ? 840.0 : 160.0;
    $sx = 500.0;
    $best = null;
    $bestD = INF;
    foreach ($s['discs'] as $i => [$x, $y, $gone]) {
        $mine = $i >= 1 && $i <= 9 ? 0 : ($i >= 10 && $i <= 18 ? 1 : null);
        if ($gone || $mine !== $colour) {
            continue;
        }
        $d = hypot($x - $sx, $y - $sy);
        if ($d < $bestD) {
            $bestD = $d;
            $best = [$x, $y];
        }
    }
    $best ??= [500.0, 500.0];
    $a = atan2($best[1] - $sy, $best[0] - $sx);
    return ['type' => 'shoot', 'x' => $sx, 'dirX' => cos($a), 'dirY' => sin($a), 'power' => 0.6];
}

/** Plays the human seat until the match ends; returns [final state, bot actions seen]. */
function playOut(string $token, int $gameId, string $kind, int $limitSeconds): array
{
    $t0 = microtime(true);
    $botMoves = 0;
    $lastSeq = null;
    while (true) {
        $s = view($token, $gameId);
        if ($s['phase'] === 'gameOver') {
            return [$s, $botMoves];
        }
        if (microtime(true) - $t0 > $limitSeconds) {
            call('POST', "/games/$gameId/actions", $token, ['type' => 'leave']);
            return [view($token, $gameId), $botMoves];
        }
        $me = $s['you'];
        $seq = json_encode([$s['lastResult']['seq'] ?? null, $s['lastShot']['seq'] ?? null, $s['die'] ?? null, $s['turn'] ?? null, $s['turnPos'] ?? null]);
        $current = $kind === 'poker' ? ($s['turnOrder'] === [] ? null : $s['turnOrder'][$s['turnPos']]) : $s['turn'];
        if ($lastSeq !== null && $seq !== $lastSeq && $current !== $me) {
            $botMoves++;
        }
        $lastSeq = $seq;
        $body = null;
        if ($kind === 'ludo' && $s['phase'] === 'playerTurn' && $s['turn'] === $me) {
            $body = $s['mustRoll'] ? ['type' => 'roll'] : ['type' => 'move', 'token' => $s['movable'][0]];
        } elseif ($kind === 'pool' && $s['turn'] === $me) {
            if ($s['phase'] === 'pushOutChoice') {
                $body = ['type' => 'push_out_answer', 'shoot' => true];
            } elseif ($s['phase'] === 'playerTurn') {
                $body = aimAt($s, $s['isBreakShot'] ? 1 : min($s['onTable']), $s['behindHeadString']);
            }
        } elseif ($kind === 'carrom' && $s['phase'] === 'playerTurn' && $s['turn'] === $me) {
            $body = carromShot($s, $me);
        } elseif ($kind === 'poker') {
            if ($s['phase'] === 'determiningBreak' && !$s['players'][$me]['picked']) {
                $body = ['type' => 'pick_break', 'index' => array_search(true, $s['breakSpread'], true)];
            } elseif ($current === $me && $s['phase'] === 'declarePhase') {
                $body = ['type' => 'declare'];
            } elseif ($current === $me && $s['phase'] === 'playerTurn') {
                if ($s['isBreakShot']) {
                    $body = aimAt($s, 1, true);
                } elseif ($s['selectedCard'] === null && $s['selectedFreeBall'] === null) {
                    foreach ($s['players'][$me]['hand'] as $c) {
                        if (!$c['completed'] && $c['id'] !== null && !in_array(PokerEngine::ball($c['id']), $s['players'][$me]['completedBalls'], true)) {
                            [$st] = call('POST', "/games/$gameId/actions", $token, ['type' => 'select_card', 'cardId' => $c['id']]);
                            if ($st === 200) {
                                break;
                            }
                        }
                    }
                    continue;
                } else {
                    $target = $s['selectedCard'] !== null ? PokerEngine::ball($s['selectedCard']) : $s['selectedFreeBall'];
                    $body = aimAt($s, $target, false);
                }
            }
        }
        if ($body !== null) {
            call('POST', "/games/$gameId/actions", $token, $body);
        }
        usleep(250000);
    }
}

[$st, $g] = call('POST', '/auth/guest', null, ['displayName' => 'BotTester']);
check($st === 200, 'guest');
$token = $g['token'];

// --- Ludo, staked: winner takes 40, buy-in 21.
$before = coins($token);
$room = matchWithBots($token, 'ludo2', 0);
[$s, $moves] = playOut($token, $room['gameId'], 'ludo', 600);
check($s['phase'] === 'gameOver', 'ludo: match finished');
check($moves > 5, "ludo: the bot played ($moves turns seen)");
$won = $s['winner'] === $s['you'];
check(coins($token) - $before === ($won ? 19 : -21), 'ludo: coins settled (' . ($won ? 'won' : 'lost') . ')');
echo '  ludo: ', $won ? 'human' : 'bot', " won\n";

// --- Carrom, staked: the bot pockets its pieces, covers the queen and the match ends.
$before = coins($token);
$room = matchWithBots($token, 'carrom', 0);
[$s, $moves] = playOut($token, $room['gameId'], 'carrom', 600);
check($s['phase'] === 'gameOver', 'carrom: match finished');
check($moves > 3, "carrom: the bot played ($moves strokes seen)");
$won = $s['winner'] === $s['you'];
check(coins($token) - $before === ($won ? 19 : -21), 'carrom: coins settled (' . ($won ? 'won' : 'lost') . ')');
check($s['players'][$s['winner']]['pocketed'] === 9 || $s['winReason'] === 'OPPONENT LEFT', 'carrom: winner pocketed nine');
echo '  carrom: ', $won ? 'human' : 'bot', " won\n";

// --- Nine-ball, free.
$room = matchWithBots($token, 'nine', null);
[$s, $moves] = playOut($token, $room['gameId'], 'pool', 600);
check($s['phase'] === 'gameOver', 'nine: match finished');
check($moves > 0, "nine: the bot shot ($moves turns seen)");
echo '  nine: ', $s['winner'] === $s['you'] ? 'human' : 'bot', ' won (', $s['winReason'] ?? '', ")\n";

// --- Billiard Poker, staked: the bot picks a break card, reveals cards and shoots.
$before = coins($token);
$room = matchWithBots($token, 'poker', 0);
[$s, $moves] = playOut($token, $room['gameId'], 'poker', 420);
check($s['phase'] === 'gameOver', 'poker: match finished');
check($moves > 0, "poker: the bot played ($moves turns seen)");
$botShots = array_sum(array_map(static fn ($p) => $p['stats']['shots'] ?? 0, array_filter($s['players'], static fn ($p, $i) => $i !== $s['you'], ARRAY_FILTER_USE_BOTH)));
check($botShots > 0, "poker: the bot took shots ($botShots)");
echo '  poker: ', $s['winner'] === $s['you'] ? 'human' : 'bot', " won\n";

// --- Bots stay off the leaderboard.
$board = call('GET', '/leaderboard', $token)[1]['entries'];
check(array_filter($board, static fn ($e) => in_array($e['name'], ['Rafi_Pro', 'Nadia22', 'KingAyan'], true)) === [], 'bots are not ranked');

echo "OK - $passed checks passed\n";
