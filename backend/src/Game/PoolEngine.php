<?php
declare(strict_types=1);

namespace App\Game;

use App\ApiError;

/**
 * 9-Ball, 8-Ball and 10-Ball rules, server side. Same rulings as the app's
 * lib/game/pool/pool_rules.dart.
 */
final class PoolEngine
{
    private const BALLS = ['nine' => 9, 'eight' => 15, 'ten' => 10];
    private const MONEY = ['nine' => 9, 'eight' => 8, 'ten' => 10];

    private static function rotation(string $kind): bool
    {
        return $kind !== 'eight';
    }

    public static function groupOf(int $ball): string
    {
        return $ball === 8 ? 'none' : ($ball < 8 ? 'solids' : 'stripes');
    }

    private static function other(string $group): string
    {
        return ['solids' => 'stripes', 'stripes' => 'solids', 'none' => 'none'][$group];
    }

    /** @param list<array{uid:int,name:string,avatar:string}> $players @return array<string,mixed> */
    public static function newState(string $kind, array $players, int $shotSeconds, int $nowMs): array
    {
        // Rack rows front to back; the app lays the numbers out in this order.
        if ($kind === 'nine') {
            $rest = [2, 3, 4, 5, 6, 7, 8];
            shuffle($rest);
            $rows = [1, 2, 3, 2, 1];
            $order = [1, $rest[0], $rest[1], $rest[2], 9, $rest[3], $rest[4], $rest[5], $rest[6]];
        } elseif ($kind === 'ten') {
            $rest = [2, 3, 4, 5, 6, 7, 8, 9];
            shuffle($rest);
            $rows = [1, 2, 3, 4];
            $order = [1, $rest[0], $rest[1], $rest[2], 10, $rest[3], $rest[4], $rest[5], $rest[6], $rest[7]];
        } else {
            $rest = array_values(array_diff(range(1, 15), [8]));
            shuffle($rest);
            $rows = [1, 2, 3, 4, 5];
            $order = array_merge(array_slice($rest, 0, 4), [8], array_slice($rest, 4));
        }
        return [
            'kind' => $kind, 'phase' => 'playerTurn', 'turn' => random_int(0, 1),
            'players' => array_map(static fn (array $p): array => [
                'uid' => $p['uid'], 'name' => $p['name'], 'avatar' => $p['avatar'], 'cue' => $p['cue'] ?? 'classic',
                'out' => false, 'missed' => 0,
                'group' => 'none', 'consecutiveFouls' => 0, 'shots' => 0, 'ballsPocketed' => 0, 'fouls' => 0,
            ], $players),
            'isBreakShot' => true, 'ballInHand' => true, 'behindHeadString' => true,
            'pushOutAvailable' => false, 'pushOutDeclared' => false, 'calledPocket' => null,
            'shotNumber' => 0, 'winner' => null, 'winReason' => null, 'lastResult' => null, 'resultSeq' => 0,
            'rackRows' => $rows, 'rackOrder' => $order, 'onTable' => range(1, self::BALLS[$kind]),
            'balls' => Physics::rack($rows, $order), 'shot' => null, 'lastShot' => null, 'shotSeq' => 0,
            'shotSeconds' => $shotSeconds, 'deadline' => $nowMs + 4000 + $shotSeconds * 1000,
        ];
    }

    /** @param array<string,mixed> $s */
    public static function onEight(array $s): bool
    {
        if ($s['kind'] !== 'eight') {
            return false;
        }
        $group = $s['players'][$s['turn']]['group'];
        if ($group === 'none') {
            return false;
        }
        foreach ($s['onTable'] as $b) {
            if (self::groupOf($b) === $group) {
                return false;
            }
        }
        return true;
    }

    /** Balls the cue ball may legally contact first. @return list<int> */
    public static function legalTargets(array $s): array
    {
        $on = $s['onTable'];
        if ($on === []) {
            return [];
        }
        if (self::rotation($s['kind'])) {
            return [min($on)];
        }
        if ($s['isBreakShot']) {
            return $on;
        }
        $group = $s['players'][$s['turn']]['group'];
        if ($group === 'none') {
            return array_values(array_filter($on, static fn (int $b): bool => $b !== 8));
        }
        $own = array_values(array_filter($on, static fn (int $b): bool => self::groupOf($b) === $group));
        return $own === [] ? [8] : $own;
    }

    /** @param array<string,mixed> $s */
    private static function requireTurn(array $s, int $pi, string $phase = 'playerTurn'): void
    {
        if ($s['phase'] !== $phase || $s['turn'] !== $pi) {
            throw ApiError::conflict('It is not your turn', 'not_your_turn');
        }
    }

    // ------------------------------------------------------------ actions

    public static function callPocket(array &$s, int $pi, int $pocket): void
    {
        self::requireTurn($s, $pi);
        if (!self::onEight($s) || $pocket < 0 || $pocket > 5) {
            throw ApiError::conflict('No pocket to call now', 'bad_call');
        }
        $s['calledPocket'] = $pocket;
    }

    public static function togglePushOut(array &$s, int $pi): void
    {
        self::requireTurn($s, $pi);
        if (!$s['pushOutAvailable']) {
            throw ApiError::conflict('Push out is not available', 'no_push_out');
        }
        $s['pushOutDeclared'] = !$s['pushOutDeclared'];
    }

    public static function answerPushOut(array &$s, int $pi, bool $shoot, int $nowMs): void
    {
        self::requireTurn($s, $pi, 'pushOutChoice');
        if (!$shoot) {
            $s['turn'] = 1 - $s['turn'];
        }
        $s['phase'] = 'playerTurn';
        $s['deadline'] = $nowMs + 1500 + $s['shotSeconds'] * 1000;
    }

    /** @param array<string,mixed> $params */
    public static function shoot(array &$s, int $pi, array $params, int $nowMs): void
    {
        self::requireTurn($s, $pi);
        if (self::onEight($s) && $s['calledPocket'] === null) {
            throw ApiError::conflict('Call a pocket for the 8-ball first', 'no_call');
        }
        $s['shot'] = ['seq' => ++$s['shotSeq'], 'by' => $pi] + $params;
        $s['phase'] = 'shooting';
        $s['players'][$pi]['missed'] = 0;
        $s['deadline'] = $nowMs + 25000;
    }

    /**
     * @param array<string,mixed> $s
     * @param array{firstContact:?int,pocketed:list<int>,cuePocketed:bool,railAfterContact:bool,objectBallsToRail:int,pocketOf:array<int,int>} $o
     */
    public static function resolve(array &$s, int $pi, array $o, int $nowMs): void
    {
        self::requireTurn($s, $pi, 'shooting');
        $kind = $s['kind'];
        $me = $s['turn'];
        $other = 1 - $me;
        $legal = self::legalTargets($s);
        $pushOut = $s['pushOutDeclared'];
        $money = self::MONEY[$kind];
        $wasBreak = $s['isBreakShot'];
        // Only balls that really were on the table can have been pocketed.
        $pocketed = array_values(array_intersect($o['pocketed'], $s['onTable']));

        $foul = 'none';
        if (!$pushOut) {
            if ($o['firstContact'] === null) {
                $foul = 'noContact';
            } elseif (!in_array($o['firstContact'], $legal, true)) {
                $foul = 'wrongBallFirst';
            }
        }
        if ($o['cuePocketed'] && $foul === 'none') {
            $foul = 'scratch';
        }
        if ($foul === 'none' && !$pushOut && self::rotation($kind) && $pocketed === []) {
            if (!$o['railAfterContact']) {
                $foul = 'noRail';
            } elseif ($kind === 'nine' && $wasBreak && $o['objectBallsToRail'] < 4) {
                $foul = 'illegalBreak';
            }
        }

        $winner = null;
        $reason = null;
        $continues = false;
        $assigned = null;
        $respot = [];
        $moneyDown = in_array($money, $pocketed, true);

        if (self::rotation($kind)) {
            if ($moneyDown && $foul === 'none' && !$pushOut) {
                $winner = $me;
                $reason = "$money-BALL POCKETED";
            } else {
                if ($moneyDown) {
                    $respot[] = $money;
                }
                $continues = $foul === 'none' && !$pushOut && $pocketed !== [];
                if ($foul !== 'none' && $kind === 'nine' && $s['players'][$me]['consecutiveFouls'] + 1 >= 3) {
                    $winner = $other;
                    $reason = 'THREE FOULS IN A ROW';
                }
            }
        } elseif ($wasBreak) {
            if ($moneyDown) {
                $respot[] = 8;
            }
            $continues = $foul === 'none' && array_diff($pocketed, [8]) !== [];
        } elseif ($moneyDown) {
            if (!self::onEight($s)) {
                $winner = $other;
                $reason = '8-BALL POCKETED TOO EARLY';
            } elseif ($foul !== 'none') {
                $winner = $other;
                $reason = 'FOUL WHILE POCKETING THE 8-BALL';
            } elseif (($o['pocketOf'][8] ?? -1) !== $s['calledPocket']) {
                $winner = $other;
                $reason = '8-BALL IN THE WRONG POCKET';
            } else {
                $winner = $me;
                $reason = '8-BALL IN THE CALLED POCKET';
            }
        } elseif ($foul === 'none') {
            $group = $s['players'][$me]['group'];
            if ($group === 'none' && $pocketed !== []) {
                $group = self::groupOf($pocketed[0]);
                $assigned = $group;
            }
            foreach ($pocketed as $b) {
                if ($group !== 'none' && self::groupOf($b) === $group) {
                    $continues = true;
                }
            }
        }
        $continues = $winner === null && $continues;

        // ---- apply
        $p = &$s['players'][$me];
        $p['shots']++;
        $s['shotNumber']++;
        $p['ballsPocketed'] += count($pocketed) - count($respot);
        if ($foul !== 'none') {
            $p['fouls']++;
            $p['consecutiveFouls']++;
        } elseif (!$pushOut) {
            $p['consecutiveFouls'] = 0;
        }
        unset($p);
        if ($assigned !== null) {
            $s['players'][$me]['group'] = $assigned;
            $s['players'][$other]['group'] = self::other($assigned);
        }
        $s['onTable'] = array_values(array_unique(array_merge(array_diff($s['onTable'], $pocketed), $respot)));
        sort($s['onTable']);
        $s['pushOutAvailable'] = $kind === 'nine' && $wasBreak && $foul === 'none';
        $s['pushOutDeclared'] = false;
        $s['isBreakShot'] = false;
        $s['behindHeadString'] = false;
        $s['ballInHand'] = $foul !== 'none';
        $s['calledPocket'] = null;
        $s['shot'] = null;
        $next = $continues ? $me : $other;
        $s['lastResult'] = [
            'seq' => ++$s['resultSeq'], 'player' => $me, 'foul' => $foul, 'pocketed' => $pocketed,
            'respot' => $respot, 'turnContinues' => $continues, 'nextPlayer' => $next, 'winner' => $winner,
            'reason' => $reason, 'groupAssigned' => $assigned, 'wasBreak' => $wasBreak, 'wasPushOut' => $pushOut,
        ];
        if ($winner !== null) {
            $s['winner'] = $winner;
            $s['winReason'] = $reason;
            $s['phase'] = 'gameOver';
            return;
        }
        $s['turn'] = $next;
        $s['phase'] = ($pushOut && $foul === 'none') ? 'pushOutChoice' : 'playerTurn';
        $s['deadline'] = $nowMs + 3500 + $s['shotSeconds'] * 1000;
    }

    /** Applies whatever is overdue. Returns true if the state changed. */
    public static function tick(array &$s, int $nowMs): bool
    {
        if ($s['phase'] === 'gameOver' || $nowMs <= $s['deadline'] + 1500) {
            return false;
        }
        if ($s['phase'] === 'pushOutChoice') {
            $s['phase'] = 'playerTurn';
            $s['deadline'] = $nowMs + $s['shotSeconds'] * 1000;
            return true;
        }
        $me = $s['turn'];
        $other = 1 - $me;
        $p = &$s['players'][$me];
        $p['shots']++;
        $p['fouls']++;
        $p['consecutiveFouls']++;
        $p['missed']++;
        $threeFouls = $s['kind'] === 'nine' && $p['consecutiveFouls'] >= 3;
        $absent = $p['missed'] >= 3;
        unset($p);
        $winner = ($threeFouls || $absent) ? $other : null;
        $reason = $threeFouls ? 'THREE FOULS IN A ROW' : ($absent ? 'OPPONENT LEFT THE GAME' : null);
        $s['shotNumber']++;
        $s['pushOutAvailable'] = false;
        $s['pushOutDeclared'] = false;
        $s['ballInHand'] = true;
        $s['calledPocket'] = null;
        $s['shot'] = null;
        $s['lastResult'] = [
            'seq' => ++$s['resultSeq'], 'player' => $me, 'foul' => 'timeout', 'pocketed' => [], 'respot' => [],
            'turnContinues' => false, 'nextPlayer' => $other, 'winner' => $winner, 'reason' => $reason,
            'groupAssigned' => null, 'wasBreak' => false, 'wasPushOut' => false,
        ];
        if ($winner !== null) {
            $s['winner'] = $winner;
            $s['winReason'] = $reason;
            $s['phase'] = 'gameOver';
            return true;
        }
        $s['turn'] = $other;
        $s['phase'] = 'playerTurn';
        $s['deadline'] = $nowMs + 3500 + $s['shotSeconds'] * 1000;
        return true;
    }

    public static function forfeit(array &$s, int $pi, int $nowMs): void
    {
        if ($s['phase'] === 'gameOver') {
            return;
        }
        $s['players'][$pi]['out'] = true;
        $s['winner'] = 1 - $pi;
        $s['winReason'] = 'OPPONENT LEFT THE GAME';
        $s['phase'] = 'gameOver';
        $s['shot'] = null;
    }

    /** Nothing is hidden in these games; the view only adds the viewer's seat. */
    public static function view(array $s, int $pi): array
    {
        return ['you' => $pi] + $s;
    }
}
