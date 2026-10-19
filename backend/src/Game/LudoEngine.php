<?php
declare(strict_types=1);

namespace App\Game;

use App\ApiError;

/**
 * Classic Ludo, server-authoritative: the server rolls the die (anti-cheat)
 * and applies every move. A line-for-line mirror of lib/game/ludo/ludo_rules.dart
 * - the rules must give the same answer on both sides.
 *
 * Token position (`step`): -1 base, 0..50 main ring, 51..55 home column,
 * 56 home (reached only by an exact roll). Ring cell = (START[colour] + step) % 52.
 */
final class LudoEngine
{
    private const RING = 52;
    private const HOME = 56;
    public const START = [0, 13, 26, 39]; // red, green, yellow, blue
    public const SAFE = [0, 8, 13, 21, 26, 34, 39, 47];

    /** @param list<array{uid:int,name:string,avatar:string,cue?:string}> $players */
    public static function newState(int $seats, array $players, int $shotSeconds, int $nowMs, array $meta = []): array
    {
        // 2 players sit opposite (red / yellow); 4 players take all four colours.
        $colours = $seats === 2 ? [0, 2] : [0, 1, 2, 3];
        $p = [];
        foreach ($players as $i => $pl) {
            $p[] = [
                'uid' => $pl['uid'], 'name' => $pl['name'], 'avatar' => $pl['avatar'], 'cue' => $pl['cue'] ?? 'classic',
                'colour' => $colours[$i], 'tokens' => [-1, -1, -1, -1], 'finished' => 0, 'missed' => 0, 'out' => false,
            ];
        }
        return [
            'kind' => 'ludo', 'phase' => 'playerTurn', 'seats' => $seats, 'players' => $p,
            'turn' => random_int(0, $seats - 1), 'die' => null, 'sixes' => 0, 'mustRoll' => true, 'movable' => null,
            'shotNumber' => 0, 'winner' => null, 'winReason' => null, 'lastResult' => null, 'resultSeq' => 0,
            'shotSeconds' => $shotSeconds, 'deadline' => $nowMs + $shotSeconds * 1000,
            'bet' => $meta + ['mode' => 'friendly', 'level' => null, 'stake' => 0, 'prize' => 0, 'multiplier' => null],
        ];
    }

    private static function ringCell(int $colour, int $step): int
    {
        return (self::START[$colour] + $step) % self::RING;
    }

    private static function onRing(int $step): bool
    {
        return $step >= 0 && $step <= 50;
    }

    private static function canMove(array $s, int $seat, int $token, int $die): bool
    {
        $step = $s['players'][$seat]['tokens'][$token];
        if ($step === self::HOME) {
            return false;
        }
        if ($step === -1) {
            return $die === 6;
        }
        return $step + $die <= self::HOME;
    }

    /** @return list<int> */
    private static function movableTokens(array $s, int $seat, int $die): array
    {
        $out = [];
        for ($t = 0; $t < 4; $t++) {
            if (self::canMove($s, $seat, $t, $die)) {
                $out[] = $t;
            }
        }
        return $out;
    }

    /** @return array<string,mixed> the view after this player's own filtered state */
    public static function view(array $s, int $pi): array
    {
        $players = array_map(static fn (array $p): array => [
            'name' => $p['name'], 'avatar' => $p['avatar'], 'cue' => $p['cue'] ?? 'classic', 'colour' => $p['colour'],
            'tokens' => $p['tokens'], 'finished' => $p['finished'], 'missed' => $p['missed'] ?? 0, 'out' => $p['out'],
        ], $s['players']);
        return [
            'kind' => 'ludo', 'phase' => $s['phase'], 'you' => $pi, 'seats' => $s['seats'], 'players' => $players,
            'turn' => $s['turn'], 'die' => $s['die'], 'sixes' => $s['sixes'], 'mustRoll' => $s['mustRoll'],
            'movable' => $s['movable'], 'shotNumber' => $s['shotNumber'], 'winner' => $s['winner'],
            'winReason' => $s['winReason'], 'lastResult' => $s['lastResult'], 'shotSeconds' => $s['shotSeconds'],
            'deadline' => $s['deadline'], 'bet' => $s['bet'] ?? null, 'lastRoll' => $s['lastRoll'] ?? null,
        ];
    }

    /** The shot clock ran out: roll or move automatically, counting a miss. */
    public static function tick(array &$s, int $nowMs): bool
    {
        if ($s['phase'] === 'gameOver' || $nowMs <= $s['deadline'] + 1500) {
            return false;
        }
        $seat = $s['turn'];
        $s['players'][$seat]['missed']++;
        if ($s['players'][$seat]['missed'] >= 3) {
            $s['players'][$seat]['out'] = true;
            $active = [];
            for ($i = 0; $i < $s['seats']; $i++) {
                if (!$s['players'][$i]['out']) {
                    $active[] = $i;
                }
            }
            if (count($active) === 1) {
                $s['winner'] = $active[0];
                $s['winReason'] = 'OPPONENTS LEFT';
                $s['phase'] = 'gameOver';
                $s['die'] = null;
                $s['movable'] = null;
                return true;
            }
        }
        // Play the turn out for the absent player: roll, then move if possible.
        if ($s['mustRoll']) {
            $moves = self::applyRoll($s, random_int(1, 6), $nowMs);
            if ($moves !== []) {
                self::applyMove($s, $moves[0], $nowMs);
            }
        } else {
            self::applyMove($s, $s['movable'][0] ?? 0, $nowMs);
        }
        return true;
    }

    /** A player gives up (left the table). */
    public static function forfeit(array &$s, int $seat, int $nowMs): void
    {
        if ($s['phase'] === 'gameOver') {
            return;
        }
        $s['players'][$seat]['out'] = true;
        $active = [];
        for ($i = 0; $i < $s['seats']; $i++) {
            if (!$s['players'][$i]['out']) {
                $active[] = $i;
            }
        }
        if (count($active) <= 1) {
            $s['winner'] = $active[0] ?? $seat;
            $s['winReason'] = 'OPPONENTS LEFT';
            $s['phase'] = 'gameOver';
            $s['die'] = null;
            $s['movable'] = null;
            return;
        }
        if ($s['turn'] === $seat) {
            self::advanceTurn($s, $nowMs);
        }
    }

    /** Action: the server rolls the die for the player whose turn it is. */
    public static function roll(array &$s, int $seat, int $nowMs): void
    {
        if ($s['phase'] !== 'playerTurn') {
            throw ApiError::conflict('The match is over', 'wrong_phase');
        }
        if ($s['turn'] !== $seat) {
            throw ApiError::conflict('It is not your turn', 'not_your_turn');
        }
        if (!$s['mustRoll']) {
            throw ApiError::conflict('Move a token first', 'must_move');
        }
        self::applyRoll($s, random_int(1, 6), $nowMs);
    }

    /** Action: move a token the current die allows. */
    public static function move(array &$s, int $seat, int $token, int $nowMs): void
    {
        if ($s['phase'] !== 'playerTurn') {
            throw ApiError::conflict('The match is over', 'wrong_phase');
        }
        if ($s['turn'] !== $seat) {
            throw ApiError::conflict('It is not your turn', 'not_your_turn');
        }
        if ($s['mustRoll'] || $s['die'] === null) {
            throw ApiError::conflict('Roll the die first', 'must_roll');
        }
        if (!in_array($token, $s['movable'] ?? [], true)) {
            throw ApiError::conflict('That token cannot move', 'bad_token');
        }
        self::applyMove($s, $token, $nowMs);
    }

    /** @return list<int> movable tokens; empty when the turn passed */
    private static function applyRoll(array &$s, int $die, int $nowMs): array
    {
        $s['die'] = $die;
        if ($die === 6) {
            $s['sixes']++;
        }
        // Every roll is shown to all players, including ones that pass the turn.
        $s['rollSeq'] = ($s['rollSeq'] ?? 0) + 1;
        $s['lastRoll'] = ['seq' => $s['rollSeq'], 'seat' => $s['turn'], 'die' => $die, 'dead' => false, 'three' => false];
        if ($s['sixes'] >= 3) {
            $s['lastRoll']['dead'] = true;
            $s['lastRoll']['three'] = true;
            self::pass($s, $nowMs);
            return [];
        }
        $moves = self::movableTokens($s, $s['turn'], $die);
        if ($moves === []) {
            $s['lastRoll']['dead'] = true;
            self::pass($s, $nowMs);
            return [];
        }
        $s['mustRoll'] = false;
        $s['movable'] = $moves;
        return $moves;
    }

    private static function applyMove(array &$s, int $token, int $nowMs): void
    {
        $die = $s['die'];
        $seat = $s['turn'];
        $from = $s['players'][$seat]['tokens'][$token];
        $six = $die === 6;
        $to = $from === -1 ? 0 : $from + $die;
        $s['players'][$seat]['tokens'][$token] = $to;

        $captured = [];
        if (self::onRing($to)) {
            $cell = self::ringCell($s['players'][$seat]['colour'], $to);
            if (!in_array($cell, self::SAFE, true)) {
                for ($os = 0; $os < $s['seats']; $os++) {
                    if ($os === $seat || $s['players'][$os]['out']) {
                        continue;
                    }
                    for ($ot = 0; $ot < 4; $ot++) {
                        $ostep = $s['players'][$os]['tokens'][$ot];
                        if (self::onRing($ostep) && self::ringCell($s['players'][$os]['colour'], $ostep) === $cell) {
                            $s['players'][$os]['tokens'][$ot] = -1;
                            $captured[] = $os * 4 + $ot;
                        }
                    }
                }
            }
        }

        $finishedToken = $to === self::HOME;
        if ($finishedToken) {
            $s['players'][$seat]['finished']++;
        }
        $won = $s['players'][$seat]['finished'] === 4;
        $s['shotNumber']++;
        $extra = $six || $captured !== [] || $finishedToken;
        $s['players'][$seat]['missed'] = 0;

        $s['lastResult'] = [
            'seq' => ++$s['resultSeq'], 'player' => $seat, 'token' => $token, 'from' => $from, 'to' => $to,
            'die' => $die, 'captured' => $captured, 'finishedToken' => $finishedToken, 'extraTurn' => $extra && !$won,
        ];

        if ($won) {
            $s['winner'] = $seat;
            $s['winReason'] = 'ALL TOKENS HOME';
            $s['phase'] = 'gameOver';
            $s['die'] = null;
            $s['movable'] = null;
            $s['mustRoll'] = false;
            return;
        }

        $s['die'] = null;
        $s['movable'] = null;
        if ($extra) {
            if (!$six) {
                $s['sixes'] = 0;
            }
            $s['mustRoll'] = true;
            $s['deadline'] = $nowMs + $s['shotSeconds'] * 1000;
        } else {
            self::advanceTurn($s, $nowMs);
        }
    }

    private static function pass(array &$s, int $nowMs): void
    {
        $s['die'] = null;
        $s['movable'] = null;
        self::advanceTurn($s, $nowMs);
    }

    private static function advanceTurn(array &$s, int $nowMs): void
    {
        $s['sixes'] = 0;
        $s['mustRoll'] = true;
        $next = $s['turn'];
        for ($i = 0; $i < $s['seats']; $i++) {
            $next = ($next + 1) % $s['seats'];
            if (!$s['players'][$next]['out']) {
                break;
            }
        }
        $s['turn'] = $next;
        $s['deadline'] = $nowMs + $s['shotSeconds'] * 1000;
    }
}
