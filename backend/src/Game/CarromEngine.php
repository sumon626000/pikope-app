<?php
declare(strict_types=1);

namespace App\Game;

use App\ApiError;

/**
 * Carrom ("disc pool" rules), server-authoritative. A line-for-line mirror of
 * lib/game/carrom/carrom_rules.dart: the rules must give the same answer on
 * both sides. The discs live in $s['discs'] ([x, y, gone] x 20) and the
 * simulation is CarromPhysics; GameService::playCarromShot ties them together.
 */
final class CarromEngine
{
    public const PIECES_EACH = 9;

    /** @param list<array{uid:int,name:string,avatar:string,cue?:string}> $players */
    public static function newState(array $players, int $shotSeconds, int $nowMs, array $meta = []): array
    {
        $p = [];
        foreach ($players as $i => $pl) {
            $p[] = [
                'uid' => $pl['uid'], 'name' => $pl['name'], 'avatar' => $pl['avatar'], 'cue' => $pl['cue'] ?? 'classic',
                'colour' => $i, 'pocketed' => 0, 'hasQueen' => false, 'missed' => 0, 'out' => false,
            ];
        }
        return [
            'kind' => 'carrom', 'phase' => 'playerTurn', 'seats' => 2, 'players' => $p,
            'turn' => random_int(0, 1), 'discs' => CarromPhysics::opening(), 'queenPending' => null,
            'shotNumber' => 0, 'shotSeq' => 0, 'resultSeq' => 0, 'lastShot' => null, 'lastResult' => null,
            'winner' => null, 'winReason' => null,
            'shotSeconds' => $shotSeconds, 'deadline' => $nowMs + $shotSeconds * 1000,
            'bet' => $meta + ['mode' => 'friendly', 'level' => null, 'stake' => 0, 'prize' => 0, 'multiplier' => null],
        ];
    }

    /** @return array<string,mixed> */
    public static function view(array $s, int $pi): array
    {
        $players = array_map(static fn (array $p): array => [
            'name' => $p['name'], 'avatar' => $p['avatar'], 'cue' => $p['cue'] ?? 'classic', 'colour' => $p['colour'],
            'pocketed' => $p['pocketed'], 'hasQueen' => $p['hasQueen'], 'missed' => $p['missed'] ?? 0, 'out' => $p['out'],
        ], $s['players']);
        return [
            'kind' => 'carrom', 'phase' => $s['phase'], 'you' => $pi, 'seats' => 2, 'players' => $players,
            'turn' => $s['turn'], 'discs' => $s['discs'], 'queenPending' => $s['queenPending'],
            'shotNumber' => $s['shotNumber'], 'lastShot' => $s['lastShot'], 'lastResult' => $s['lastResult'],
            'winner' => $s['winner'], 'winReason' => $s['winReason'],
            'shotSeconds' => $s['shotSeconds'], 'deadline' => $s['deadline'], 'bet' => $s['bet'] ?? null,
        ];
    }

    /** The shot clock ran out: the turn passes; three misses and the player is out. */
    public static function tick(array &$s, int $nowMs): bool
    {
        if ($s['phase'] === 'gameOver' || $nowMs <= $s['deadline'] + 1500) {
            return false;
        }
        $seat = $s['turn'];
        $other = 1 - $seat;
        $s['players'][$seat]['missed']++;
        $world = CarromPhysics::fromState($s['discs']);
        $queenReturned = false;
        if ($s['queenPending'] === $seat) {
            $world->returnToCentre(CarromPhysics::QUEEN);
            $queenReturned = true;
            $s['queenPending'] = null;
        }
        $winner = null;
        $reason = null;
        if ($s['players'][$seat]['missed'] >= 3) {
            $s['players'][$seat]['out'] = true;
            $winner = $other;
            $reason = 'OPPONENT LEFT';
        }
        $s['discs'] = $world->toState();
        $s['lastResult'] = [
            'seq' => ++$s['resultSeq'], 'player' => $seat, 'foul' => false, 'pocketed' => [], 'returned' => [],
            'penalty' => null, 'queenCovered' => false, 'queenReturned' => $queenReturned, 'queenPending' => false,
            'lastPieceReturned' => false, 'extraTurn' => false, 'nextPlayer' => $other, 'winner' => $winner,
            'reason' => $reason, 'timeout' => true,
        ];
        $s['shotNumber']++;
        if ($winner !== null) {
            self::end($s, $winner, $reason);
        } else {
            $s['turn'] = $other;
            $s['deadline'] = $nowMs + $s['shotSeconds'] * 1000;
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
        self::end($s, 1 - $seat, 'OPPONENT LEFT');
    }

    private static function end(array &$s, int $winner, string $reason): void
    {
        $s['winner'] = $winner;
        $s['winReason'] = $reason;
        $s['phase'] = 'gameOver';
    }

    /** Checks a stroke may be played now and books it (before simulating). */
    public static function shoot(array &$s, int $seat, int $nowMs): void
    {
        if ($s['phase'] !== 'playerTurn') {
            throw ApiError::conflict('The match is over', 'wrong_phase');
        }
        if ($s['turn'] !== $seat) {
            throw ApiError::conflict('It is not your turn', 'not_your_turn');
        }
        $s['shotSeq']++;
    }

    /**
     * Rules on a finished stroke by $seat: credits pieces, returns what has to
     * come back (moving discs in $w) and decides who plays next.
     */
    public static function resolve(array &$s, CarromPhysics $w, int $seat, int $nowMs): void
    {
        $other = 1 - $seat;
        $me = &$s['players'][$seat];
        $them = &$s['players'][$other];
        $pocketed = $w->pocketed;
        $foul = $w->strikerPocketed;
        $own = array_values(array_filter($pocketed, static fn (int $d): bool => CarromPhysics::colourOf($d) === $me['colour']));
        $opp = array_values(array_filter($pocketed, static fn (int $d): bool => CarromPhysics::colourOf($d) === $them['colour']));
        $queenIn = in_array(CarromPhysics::QUEEN, $pocketed, true);
        $returned = [];
        $queenReturned = false;
        $queenCovered = false;
        $lastPieceReturned = false;
        $queenPendingNow = false;
        $penalty = null;
        $extra = false;
        $winner = null;
        $reason = null;

        if ($foul) {
            foreach ($pocketed as $d) {
                $w->returnToCentre($d);
                $returned[] = $d;
            }
            if ($s['queenPending'] === $seat) {
                $w->returnToCentre(CarromPhysics::QUEEN);
                $queenReturned = true;
                $s['queenPending'] = null;
            }
            if ($me['pocketed'] > 0) {
                for ($i = 1; $i < CarromPhysics::COUNT; $i++) {
                    if ($w->gone[$i] && CarromPhysics::colourOf($i) === $me['colour']) {
                        $w->returnToCentre($i);
                        $penalty = $i;
                        $me['pocketed']--;
                        break;
                    }
                }
            }
        } else {
            $queenOwned = $me['hasQueen'] || $them['hasQueen'] || $queenIn || $s['queenPending'] === $seat;
            $ownCount = count($own);
            $oppCount = count($opp);
            if ($me['pocketed'] + $ownCount >= self::PIECES_EACH && !$queenOwned) {
                $last = $own[count($own) - 1];
                $w->returnToCentre($last);
                $returned[] = $last;
                $ownCount--;
                $lastPieceReturned = true;
            }
            if ($them['pocketed'] + $oppCount >= self::PIECES_EACH && !($me['hasQueen'] || $them['hasQueen'] || $queenIn)) {
                $last = $opp[count($opp) - 1];
                $w->returnToCentre($last);
                $returned[] = $last;
                $oppCount--;
            }
            $them['pocketed'] += $oppCount;
            if ($s['queenPending'] === $seat) {
                if ($ownCount > 0) {
                    $me['hasQueen'] = true;
                    $queenCovered = true;
                } else {
                    $w->returnToCentre(CarromPhysics::QUEEN);
                    $queenReturned = true;
                }
                $s['queenPending'] = null;
            }
            if ($queenIn) {
                if ($ownCount > 0) {
                    $me['hasQueen'] = true;
                    $queenCovered = true;
                } else {
                    $s['queenPending'] = $seat;
                    $queenPendingNow = true;
                }
            }
            $me['pocketed'] += $ownCount;
            $extra = $ownCount > 0 || $queenIn;
            if ($me['pocketed'] >= self::PIECES_EACH) {
                $winner = $seat;
                $reason = 'ALL PIECES POCKETED';
            } elseif ($them['pocketed'] >= self::PIECES_EACH) {
                $winner = $other;
                $reason = 'ALL PIECES POCKETED';
            }
        }
        $w->gone[CarromPhysics::STRIKER] = true;
        $me['missed'] = 0;
        $s['shotNumber']++;
        $next = $winner !== null ? $seat : ($extra ? $seat : $other);
        $s['lastResult'] = [
            'seq' => ++$s['resultSeq'], 'player' => $seat, 'foul' => $foul, 'pocketed' => $pocketed, 'returned' => $returned,
            'penalty' => $penalty, 'queenCovered' => $queenCovered, 'queenReturned' => $queenReturned,
            'queenPending' => $queenPendingNow, 'lastPieceReturned' => $lastPieceReturned,
            'extraTurn' => $extra && $winner === null, 'nextPlayer' => $next, 'winner' => $winner, 'reason' => $reason,
            'timeout' => false,
        ];
        unset($me, $them);
        if ($winner !== null) {
            self::end($s, $winner, $reason);
        } else {
            $s['turn'] = $next;
            $s['deadline'] = $nowMs + $s['shotSeconds'] * 1000;
        }
    }
}
