<?php
declare(strict_types=1);

namespace App\Game;

use App\Config;

/**
 * Stand-in players for online tables nobody else joined. Only decisions live
 * here: given the authoritative state, which seat acts now and what it does
 * (an action body exactly like a client would send). GameService applies it
 * through the same rules as a human's action.
 *
 * Pool and Billiard Poker shots are chosen the way the app's practice bots
 * choose them: ghost-ball aims for every legal target and pocket, the best
 * few test-run on a copy of the table and ruled by the real engine.
 */
final class Bots
{
    private const R = Physics::R;

    /** Point on each pocket mouth to aim at (same order as Physics pockets). */
    private const POCKET_AIM = [[10.0, 10.0], [500.0, 0.0], [990.0, 10.0], [10.0, 490.0], [500.0, 500.0], [990.0, 490.0]];

    /** Aiming error, radians (one standard deviation). */
    private const AIM_NOISE = 0.011;

    /** Carrom strokes shake a little more, so a person can keep up. */
    private const CARROM_AIM_NOISE = 0.024;

    /** How many candidate shots are test-run per decision. */
    private const TRIALS = 8;

    /** Think time multiplier (BOT_SPEED=10 plays ten times faster, for tests). */
    private static function speed(): float
    {
        return max(0.05, (float) Config::get('BOT_SPEED', '1'));
    }

    /**
     * The bot seat that should act now, or null. A bot waits until everyone
     * has watched the last move and then "thinks" for a moment.
     * @param array<string,mixed> $s
     */
    public static function due(array $s, int $nowMs): ?int
    {
        $bots = $s['bots'] ?? [];
        if ($bots === [] || $s['phase'] === 'gameOver') {
            return null;
        }
        $seat = null;
        $think = 1500;
        switch ($s['kind']) {
            case 'ludo':
                if ($s['phase'] !== 'playerTurn') {
                    return null;
                }
                $seat = $s['turn'];
                $think = $s['mustRoll'] ? 1100 : 800;
                break;
            case 'poker':
                if ($s['phase'] === 'determiningBreak') {
                    foreach ($bots as $i => $b) {
                        if ($s['players'][$b]['breakCard'] === null) {
                            $seat = $b;
                            $think = 1500 + 400 * $i;
                            break;
                        }
                    }
                } elseif ($s['phase'] === 'declarePhase') {
                    $seat = PokerEngine::current($s);
                    $think = 1200;
                } elseif ($s['phase'] === 'playerTurn') {
                    $seat = PokerEngine::current($s);
                    $think = !$s['isBreakShot'] && PokerEngine::targetBall($s) === null ? 1700 : 1100;
                } else {
                    return null;
                }
                break;
            default:
                if ($s['phase'] !== 'playerTurn' && $s['phase'] !== 'pushOutChoice') {
                    return null;
                }
                $seat = $s['turn'];
                $think = 2000;
        }
        if ($seat === null || !in_array($seat, $bots, true) || ($s['players'][$seat]['out'] ?? false)) {
            return null;
        }
        // The turn effectively starts when its clock does (after any shot
        // replay or deal animation), or at the last action, whichever is later.
        $last = (int) ($s['lastActMs'] ?? 0);
        $turnStart = (int) $s['deadline'] - (int) $s['shotSeconds'] * 1000;
        $jitter = ((int) ($s['resultSeq'] ?? 0) * 7919 + (int) ($s['shotSeq'] ?? 0) * 104729 + $seat * 31) % 700;
        $wait = (max(0, $turnStart - $last) + $think + $jitter) / self::speed();
        return $nowMs >= $last + (int) $wait ? $seat : null;
    }

    /**
     * What the bot at $seat does now: an action body for GameService.
     * @param array<string,mixed> $s @return array<string,mixed>
     */
    public static function decide(array $s, int $seat, int $nowMs): array
    {
        return match ($s['kind']) {
            'ludo' => self::ludo($s, $seat),
            'carrom' => self::carrom($s, $seat),
            'poker' => self::poker($s, $seat, $nowMs),
            default => self::pool($s, $seat, $nowMs),
        };
    }

    // ------------------------------------------------------------- Ludo

    /** Capture if possible, else bring a token home, else (often) free one on a six, else push the leader. */
    private static function ludo(array $s, int $seat): array
    {
        if ($s['mustRoll']) {
            return ['type' => 'roll'];
        }
        $moves = $s['movable'] ?? [];
        $die = (int) $s['die'];
        $p = $s['players'][$seat];
        $capture = $finish = $leave = null;
        $best = -1;
        $advance = $moves[0] ?? 0;
        foreach ($moves as $t) {
            $from = $p['tokens'][$t];
            $to = $from === -1 ? 0 : $from + $die;
            if ($to === 56) {
                $finish ??= $t;
            }
            if ($from === -1) {
                $leave ??= $t;
            }
            if ($to >= 0 && $to <= 50) {
                $cell = (LudoEngine::START[$p['colour']] + $to) % 52;
                if (!in_array($cell, LudoEngine::SAFE, true)) {
                    foreach ($s['players'] as $os => $op) {
                        if ($os === $seat || $op['out']) {
                            continue;
                        }
                        foreach ($op['tokens'] as $ostep) {
                            if ($ostep >= 0 && $ostep <= 50 && (LudoEngine::START[$op['colour']] + $ostep) % 52 === $cell) {
                                $capture ??= $t;
                            }
                        }
                    }
                }
            }
            if ($to > $best) {
                $best = $to;
                $advance = $t;
            }
        }
        $pick = $capture ?? $finish ?? ($die === 6 && $leave !== null && random_int(0, 1) === 1 ? $leave : $advance);
        return ['type' => 'move', 'token' => $pick];
    }

    // ----------------------------------------------------------- carrom

    /**
     * Mirror of lib/game/carrom/carrom_bot.dart: ghost-disc aims at every own
     * piece (and the queen) for every pocket from a few striker positions,
     * the most promising test-run on a copy of the board.
     */
    private static function carrom(array $s, int $seat): array
    {
        $world = CarromPhysics::fromState($s['discs']);
        $me = $s['players'][$seat];
        $them = $s['players'][1 - $seat];
        $own = [];
        for ($i = 1; $i < CarromPhysics::COUNT; $i++) {
            if (!$world->gone[$i] && CarromPhysics::colourOf($i) === $me['colour']) {
                $own[] = $i;
            }
        }
        $targets = $own;
        if (!$world->gone[CarromPhysics::QUEEN] && $own !== [] && $s['queenPending'] !== $seat) {
            $targets[] = CarromPhysics::QUEEN;
        }
        $baseY = $seat === 0 ? CarromPhysics::BASE_NEAR : CarromPhysics::BASE_FAR;
        $options = [];
        foreach ($targets as $t) {
            $tx = $world->x[$t];
            $ty = $world->y[$t];
            foreach (CarromPhysics::POCKETS as [$px, $py]) {
                $pdx = $px - $tx;
                $pdy = $py - $ty;
                $pd = hypot($pdx, $pdy);
                if ($pd < 1) {
                    continue;
                }
                $gx = $tx - $pdx / $pd * (CarromPhysics::STRIKER_R + CarromPhysics::PIECE_R);
                $gy = $ty - $pdy / $pd * (CarromPhysics::STRIKER_R + CarromPhysics::PIECE_R);
                foreach ([220.0, 313.0, 406.0, 500.0, 593.0, 686.0, 780.0] as $sx) {
                    if (!self::carromFits($world, $seat, $sx)) {
                        continue;
                    }
                    $dx = $gx - $sx;
                    $dy = $gy - $baseY;
                    $d = hypot($dx, $dy);
                    if ($d < 1) {
                        continue;
                    }
                    $dirX = $dx / $d;
                    $dirY = $dy / $d;
                    if ($seat === 0 ? $dirY > -0.08 : $dirY < 0.08) {
                        continue;
                    }
                    $cut = $dirX * $pdx / $pd + $dirY * $pdy / $pd;
                    if ($cut < 0.2) {
                        continue;
                    }
                    $clear = self::carromClear($world, $sx, $baseY, $gx, $gy, [CarromPhysics::STRIKER, $t]);
                    $power = max(0.25, min(1.0, 0.25 + $d / 1600 + $pd / 1800 + (1 - $cut) * 0.25));
                    $options[] = ['x' => $sx, 'dirX' => $dirX, 'dirY' => $dirY, 'power' => $power,
                        'quality' => ($clear ? 30 : 0) + $cut * 20 - $pd / 60 - $d / 120];
                }
            }
        }
        usort($options, static fn (array $a, array $b): int => $b['quality'] <=> $a['quality']);
        $best = null;
        $bestScore = -INF;
        foreach (array_slice($options, 0, 12) as $o) {
            $w = CarromPhysics::fromState($world->toState());
            $w->placeStriker($seat, $o['x']);
            $w->shoot($o['dirX'], $o['dirY'], $o['power']);
            $w->simulate();
            $ownIn = $oppIn = 0;
            $queen = false;
            foreach ($w->pocketed as $d) {
                $c = CarromPhysics::colourOf($d);
                if ($c === $me['colour']) {
                    $ownIn++;
                } elseif ($c === $them['colour']) {
                    $oppIn++;
                } else {
                    $queen = true;
                }
            }
            if ($w->strikerPocketed) {
                $score = -200.0 + $ownIn * 10;
            } else {
                $score = $ownIn * 100 - $oppIn * 70;
                $left = 0;
                for ($i = 1; $i < CarromPhysics::COUNT; $i++) {
                    if (!$w->gone[$i] && CarromPhysics::colourOf($i) === $me['colour']) {
                        $left++;
                    }
                }
                if ($queen) {
                    $score += $ownIn > 0 ? 80 : ($left > 0 ? 30 : -40);
                }
                if ($s['queenPending'] === $seat && $ownIn === 0) {
                    $score -= 60;
                }
                if ($me['pocketed'] + $ownIn >= CarromEngine::PIECES_EACH && !($me['hasQueen'] || $them['hasQueen']) && !$queen) {
                    $score -= 120;
                }
                if ($ownIn === 0 && !$queen) {
                    for ($i = 1; $i < CarromPhysics::COUNT; $i++) {
                        if ($w->gone[$i] || CarromPhysics::colourOf($i) !== $me['colour']) {
                            continue;
                        }
                        $near = INF;
                        foreach (CarromPhysics::POCKETS as [$px, $py]) {
                            $near = min($near, hypot($w->x[$i] - $px, $w->y[$i] - $py));
                        }
                        $score -= $near / 200;
                    }
                }
            }
            $score += $o['quality'];
            if ($score > $bestScore) {
                $bestScore = $score;
                $best = $o;
            }
        }
        if ($best === null) {
            // Nothing lined up: nudge the nearest piece gently.
            $x = self::carromFits($world, $seat, 500.0) ? 500.0 : 400.0;
            $tx = 500.0;
            $ty = 500.0;
            $bestD = INF;
            for ($i = 1; $i < CarromPhysics::COUNT; $i++) {
                if ($world->gone[$i]) {
                    continue;
                }
                $d = hypot($world->x[$i] - $x, $world->y[$i] - $baseY);
                if ($d < $bestD) {
                    $bestD = $d;
                    $tx = $world->x[$i];
                    $ty = $world->y[$i];
                }
            }
            $d = max(1e-9, hypot($tx - $x, $ty - $baseY));
            return ['type' => 'shoot', 'x' => $x, 'dirX' => ($tx - $x) / $d, 'dirY' => ($ty - $baseY) / $d, 'power' => 0.45];
        }
        $a = atan2($best['dirY'], $best['dirX']) + self::gauss() * self::CARROM_AIM_NOISE;
        $power = max(0.25, min(1.0, $best['power'] + (mt_rand() / mt_getrandmax() - 0.5) * 0.08));
        return ['type' => 'shoot', 'x' => $best['x'], 'dirX' => cos($a), 'dirY' => sin($a), 'power' => $power];
    }

    private static function carromFits(CarromPhysics $w, int $seat, float $sx): bool
    {
        $sy = $seat === 0 ? CarromPhysics::BASE_NEAR : CarromPhysics::BASE_FAR;
        for ($i = 1; $i < CarromPhysics::COUNT; $i++) {
            if (!$w->gone[$i] && hypot($w->x[$i] - $sx, $w->y[$i] - $sy) < CarromPhysics::STRIKER_R + CarromPhysics::PIECE_R + 0.5) {
                return false;
            }
        }
        return true;
    }

    /** @param list<int> $ignore */
    private static function carromClear(CarromPhysics $w, float $ax, float $ay, float $bx, float $by, array $ignore): bool
    {
        $sx = $bx - $ax;
        $sy = $by - $ay;
        $len2 = $sx * $sx + $sy * $sy;
        if ($len2 == 0) {
            return true;
        }
        for ($i = 0; $i < CarromPhysics::COUNT; $i++) {
            if ($w->gone[$i] || in_array($i, $ignore, true)) {
                continue;
            }
            $t = max(0.0, min(1.0, (($w->x[$i] - $ax) * $sx + ($w->y[$i] - $ay) * $sy) / $len2));
            if (hypot($ax + $sx * $t - $w->x[$i], $ay + $sy * $t - $w->y[$i]) < CarromPhysics::STRIKER_R + CarromPhysics::PIECE_R - 0.5) {
                return false;
            }
        }
        return true;
    }

    // ------------------------------------------------------------- pool

    private static function pool(array $s, int $seat, int $nowMs): array
    {
        if ($s['phase'] === 'pushOutChoice') {
            return ['type' => 'push_out_answer', 'shoot' => true];
        }
        if ($s['isBreakShot']) {
            return self::breakShot($s);
        }
        $plan = self::plan($s, $seat, PoolEngine::legalTargets($s), $nowMs, false);
        if (PoolEngine::onEight($s) && $s['calledPocket'] === null) {
            return ['type' => 'call_pocket', 'pocket' => $plan['pocket']];
        }
        return $plan['body'];
    }

    // ---------------------------------------------------- Billiard Poker

    private static function poker(array $s, int $seat, int $nowMs): array
    {
        if ($s['phase'] === 'determiningBreak') {
            $free = array_keys(array_filter($s['breakSpread'], static fn ($c) => $c !== null));
            return ['type' => 'pick_break', 'index' => $free[random_int(0, count($free) - 1)]];
        }
        if ($s['phase'] === 'declarePhase') {
            return ['type' => 'declare'];
        }
        if ($s['isBreakShot']) {
            return self::breakShot($s);
        }
        $p = $s['players'][$seat];
        $target = PokerEngine::targetBall($s);
        if ($target !== null) {
            return self::plan($s, $seat, [$target], $nowMs, true)['body'];
        }
        // Reveal the card (or nominate the free ball) with the best shot.
        $pending = PokerEngine::pending($p);
        $plan = self::plan($s, $seat, array_values(array_unique(array_merge($pending, PokerEngine::FREE_BALLS))), $nowMs, true);
        $ball = $plan['ball'];
        if (in_array($ball, $pending, true)) {
            foreach ($p['hand'] as $c) {
                if (!$c['completed'] && PokerEngine::ball($c['id']) === $ball) {
                    return ['type' => 'select_card', 'cardId' => $c['id']];
                }
            }
        }
        return ['type' => 'select_free', 'ball' => in_array($ball, PokerEngine::FREE_BALLS, true) ? $ball : PokerEngine::FREE_BALLS[0]];
    }

    // ------------------------------------------------------------ shots

    /** Opening break: cue behind the head string, hard at the apex ball. */
    private static function breakShot(array $s): array
    {
        $balls = $s['balls'];
        $cx = Physics::HEAD_STRING_X - 4;
        $cy = 250 + (mt_rand() / mt_getrandmax() - 0.5) * 60;
        $apex = null;
        $bestD = INF;
        for ($i = 1; $i < 16; $i++) {
            if (!$balls[$i][2]) {
                $d = hypot($balls[$i][0] - 750, $balls[$i][1] - 250);
                if ($d < $bestD) {
                    $bestD = $d;
                    $apex = $i;
                }
            }
        }
        [$tx, $ty] = $apex === null ? [750.0, 250.0] : [$balls[$apex][0], $balls[$apex][1]];
        $a = atan2($ty - $cy, $tx - $cx) + self::gauss() * self::AIM_NOISE * 0.4;
        return ['type' => 'shoot', 'dirX' => cos($a), 'dirY' => sin($a), 'power' => 0.9 + mt_rand(0, 100) / 1000,
            'spinX' => 0.0, 'spinY' => 0.0, 'cueX' => $cx, 'cueY' => $cy];
    }

    /**
     * Best shot at one of $targets.
     * @param list<int> $targets
     * @return array{body:array<string,mixed>,ball:int,pocket:int}
     */
    private static function plan(array $s, int $seat, array $targets, int $nowMs, bool $poker): array
    {
        $balls = $s['balls'];
        $inHand = (bool) $s['ballInHand'];
        $behind = $poker ? (bool) $s['isBreakShot'] : (bool) ($s['behindHeadString'] ?? false);
        $called = !$poker && PoolEngine::onEight($s) ? $s['calledPocket'] : null;
        $cue = [(float) $balls[0][0], (float) $balls[0][1]];

        $options = [];
        foreach ($targets as $t) {
            if ($t < 1 || $t > 15 || $balls[$t][2]) {
                continue;
            }
            $tx = (float) $balls[$t][0];
            $ty = (float) $balls[$t][1];
            foreach (self::POCKET_AIM as $pocket => [$ax, $ay]) {
                if ($called !== null && $pocket !== $called) {
                    continue;
                }
                $len = hypot($ax - $tx, $ay - $ty);
                if ($len < 1) {
                    continue;
                }
                $ux = ($ax - $tx) / $len;
                $uy = ($ay - $ty) / $len;
                $gx = $tx - $ux * 2 * self::R;
                $gy = $ty - $uy * 2 * self::R;
                if (!self::clear($balls, $tx, $ty, $ax, $ay, [$t, 0])) {
                    continue;
                }
                $c = $cue;
                if ($inHand) {
                    $c = null;
                    foreach ([260.0, 180.0, 120.0, 340.0] as $d) {
                        $px = $gx - $ux * $d;
                        $py = $gy - $uy * $d;
                        if (self::free($balls, $px, $py, $behind)) {
                            $c = [$px, $py];
                            break;
                        }
                    }
                    if ($c === null) {
                        continue;
                    }
                }
                $dx = $gx - $c[0];
                $dy = $gy - $c[1];
                $dl = hypot($dx, $dy);
                if ($dl < 1) {
                    continue;
                }
                $cut = ($dx / $dl) * $ux + ($dy / $dl) * $uy;
                if ($cut < 0.25 || !self::clear($balls, $c[0], $c[1], $gx, $gy, [$t, 0])) {
                    continue;
                }
                $travel = $dl + $len;
                $quality = $cut - $travel / 2500;
                $power = max(0.2, min(0.9, 0.22 + $travel / 1900 + (1 - $cut) * 0.25));
                $angle = atan2($dy, $dx);
                $options[] = [$t, $pocket, $angle, $power, $quality, $c];
                $options[] = [$t, $pocket, $angle, min(1.0, $power + 0.2), $quality - 0.05, $c];
            }
            // A plain full hit, so at least the first contact is right.
            $c = $cue;
            if ($inHand) {
                $c = self::spotNear($balls, $tx, $ty, $behind) ?? $cue;
            }
            $quality = self::clear($balls, $c[0], $c[1], $tx, $ty, [$t, 0]) ? -1.0 : -2.0;
            $options[] = [$t, 0, atan2($ty - $c[1], $tx - $c[0]), 0.45, $quality, $c];
        }
        if ($options === []) {
            $t = $targets[0] ?? 1;
            $a = atan2((float) $balls[$t][1] - $cue[1], (float) $balls[$t][0] - $cue[0]);
            return ['body' => self::body($a, 0.45, $inHand ? $cue : null), 'ball' => $t, 'pocket' => 0];
        }
        usort($options, static fn ($a, $b) => $b[4] <=> $a[4]);
        $best = null;
        $bestScore = -INF;
        foreach (array_slice($options, 0, self::TRIALS) as $o) {
            $score = self::trial($s, $seat, $o, $inHand, $behind, $nowMs, $poker) + $o[4] * 5;
            if ($score > $bestScore) {
                $bestScore = $score;
                $best = $o;
            }
        }
        [$t, $pocket, $angle, $power, , $c] = $best;
        $angle += self::gauss() * self::AIM_NOISE;
        $power = max(0.12, min(1.0, $power + self::gauss() * 0.04));
        return ['body' => self::body($angle, $power, $inHand ? $c : null), 'ball' => $t, 'pocket' => $pocket];
    }

    /** Test-runs one option on a copy of the table and rules on it. */
    private static function trial(array $s, int $seat, array $o, bool $inHand, bool $behind, int $nowMs, bool $poker): float
    {
        [$t, $pocket, $angle, $power, , $c] = $o;
        $world = Physics::fromState($s['balls']);
        if ($inHand && !$world->placeCue($c[0], $c[1], $behind)) {
            return -500;
        }
        $shot = ['dirX' => cos($angle), 'dirY' => sin($angle), 'power' => $power, 'spinX' => 0.0, 'spinY' => 0.0];
        $world->shoot($shot['dirX'], $shot['dirY'], $power, 0.0, 0.0);
        $world->simulate();
        $outcome = $world->outcome();
        $copy = $s;
        try {
            if ($poker) {
                if ($copy['selectedCard'] === null && $copy['selectedFreeBall'] === null) {
                    $card = null;
                    foreach ($copy['players'][$seat]['hand'] as $h) {
                        if (!$h['completed'] && PokerEngine::ball($h['id']) === $t) {
                            $card = $h['id'];
                            break;
                        }
                    }
                    $card !== null ? PokerEngine::selectCard($copy, $seat, $card) : PokerEngine::selectFreeBall($copy, $seat, $t);
                }
                PokerEngine::shoot($copy, $seat, $shot, $nowMs);
                PokerEngine::resolve($copy, $seat, $outcome, $nowMs);
                $r = $copy['lastResult'];
                if (!$r['legal']) {
                    return -100;
                }
                return ($r['becameReadyToDeclare'] ? 500 : 0) + count($r['completedObjectives']) * 60
                    + ($r['turnContinues'] ? 100 : 0);
            }
            if (PoolEngine::onEight($copy)) {
                $copy['calledPocket'] = $pocket;
            }
            PoolEngine::shoot($copy, $seat, $shot, $nowMs);
            PoolEngine::resolve($copy, $seat, $outcome, $nowMs);
        } catch (\Throwable) {
            return -500;
        }
        if ($copy['winner'] !== null) {
            return $copy['winner'] === $seat ? 1000 : -1000;
        }
        $r = $copy['lastResult'];
        if ($r['foul'] !== 'none') {
            return -100;
        }
        return $r['turnContinues'] ? 100 + count($r['pocketed']) * 5 : 0;
    }

    /** @return array<string,mixed> */
    private static function body(float $angle, float $power, ?array $cuePos): array
    {
        $b = ['type' => 'shoot', 'dirX' => cos($angle), 'dirY' => sin($angle), 'power' => $power, 'spinX' => 0.0, 'spinY' => 0.0];
        if ($cuePos !== null) {
            $b['cueX'] = $cuePos[0];
            $b['cueY'] = $cuePos[1];
        }
        return $b;
    }

    /** No ball (other than $ignore) blocks the straight path of a ball from a to b. */
    private static function clear(array $balls, float $ax, float $ay, float $bx, float $by, array $ignore): bool
    {
        $dx = $bx - $ax;
        $dy = $by - $ay;
        $len2 = $dx * $dx + $dy * $dy;
        for ($i = 0; $i < 16; $i++) {
            if ($balls[$i][2] || in_array($i, $ignore, true)) {
                continue;
            }
            $px = (float) $balls[$i][0];
            $py = (float) $balls[$i][1];
            $k = $len2 > 0 ? max(0.0, min(1.0, (($px - $ax) * $dx + ($py - $ay) * $dy) / $len2)) : 0.0;
            if (hypot($px - ($ax + $k * $dx), $py - ($ay + $k * $dy)) < 2 * self::R - 0.5) {
                return false;
            }
        }
        return true;
    }

    /** The cue ball could be placed at (x, y). */
    private static function free(array $balls, float $x, float $y, bool $behind): bool
    {
        $maxX = $behind ? Physics::HEAD_STRING_X : Physics::WIDTH - self::R;
        if ($x < self::R + 2 || $x > $maxX || $y < self::R + 2 || $y > Physics::HEIGHT - self::R - 2) {
            return false;
        }
        for ($i = 1; $i < 16; $i++) {
            if (!$balls[$i][2] && hypot($balls[$i][0] - $x, $balls[$i][1] - $y) < 2 * self::R + 1) {
                return false;
            }
        }
        return true;
    }

    /** Somewhere free to put the cue ball for a plain hit on (tx, ty). @return array{0:float,1:float}|null */
    private static function spotNear(array $balls, float $tx, float $ty, bool $behind): ?array
    {
        foreach ([[-150.0, 0.0], [150.0, 0.0], [0.0, -120.0], [0.0, 120.0], [-220.0, 60.0], [-220.0, -60.0]] as [$ox, $oy]) {
            $x = $behind ? min($tx - 150, Physics::HEAD_STRING_X - 10) : $tx + $ox;
            $y = $ty + $oy;
            if (self::free($balls, $x, $y, $behind)) {
                return [$x, $y];
            }
        }
        return null;
    }

    private static function gauss(): float
    {
        $u = max(mt_rand() / mt_getrandmax(), 1e-9);
        $v = mt_rand() / mt_getrandmax();
        return sqrt(-2 * log($u)) * cos(2 * M_PI * $v);
    }
}
