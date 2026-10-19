<?php
declare(strict_types=1);

namespace App\Game;

use App\ApiError;

/**
 * Billiard Poker rules, server side. Same rulings as the app's
 * lib/game/rules/rules_engine.dart; the server owns the deck, the deal, the
 * turn, penalties and the winner. A card is an id 0..51 = (rank-1)*4 + suit
 * with suit 0 clubs < 1 diamonds < 2 hearts < 3 spades, so a higher id is a
 * higher break card. The state is a plain array stored as JSON.
 */
final class PokerEngine
{
    public const CARDS_PER_PLAYER = 7;
    public const FREE_BALLS = [14, 15];
    public const SPREAD = 30;

    public static function ball(int $cardId): int
    {
        return intdiv($cardId, 4) + 1;
    }

    /** @return list<int> */
    private static function shuffledDeck(): array
    {
        $deck = range(0, 51);
        for ($i = 51; $i > 0; $i--) {
            $j = random_int(0, $i);
            [$deck[$i], $deck[$j]] = [$deck[$j], $deck[$i]];
        }
        return $deck;
    }

    /** @param list<array{uid:int,name:string,avatar:string}> $players @return array<string,mixed> */
    public static function newState(array $players, int $shotSeconds, int $nowMs): array
    {
        $rack = range(1, 15);
        shuffle($rack);
        return [
            'kind' => 'poker',
            'phase' => 'determiningBreak',
            'players' => array_map(static fn (array $p): array => [
                'uid' => $p['uid'], 'name' => $p['name'], 'avatar' => $p['avatar'], 'cue' => $p['cue'] ?? 'classic',
                'out' => false, 'missed' => 0, 'breakCard' => null, 'hand' => [], 'completedBalls' => [],
                'stats' => ['shots' => 0, 'ballsCompleted' => 0, 'fouls' => 0, 'penaltyCards' => 0,
                    'timeouts' => 0, 'extraShots' => 0],
            ], $players),
            'breakSpread' => array_slice(self::shuffledDeck(), 0, self::SPREAD),
            'turnOrder' => [], 'turnPos' => 0, 'deck' => [],
            'isBreakShot' => true, 'ballInHand' => true, 'extraShots' => 0,
            'selectedCard' => null, 'selectedFreeBall' => null,
            'shotNumber' => 0, 'winner' => null, 'lastResult' => null, 'resultSeq' => 0,
            'rackOrder' => $rack, 'balls' => Physics::rack([1, 2, 3, 4, 5], $rack),
            'shot' => null, 'lastShot' => null, 'shotSeq' => 0, 'nextKey' => 0,
            'shotSeconds' => $shotSeconds, 'deadline' => $nowMs + 30000,
        ];
    }

    // ------------------------------------------------------------ queries

    /** @param array<string,mixed> $p @return list<int> */
    public static function required(array $p): array
    {
        return array_values(array_unique(array_map(static fn ($c) => self::ball($c['id']), $p['hand'])));
    }

    /** @param array<string,mixed> $p @return list<int> */
    public static function pending(array $p): array
    {
        return array_values(array_diff(self::required($p), $p['completedBalls']));
    }

    /** @param array<string,mixed> $p */
    public static function ready(array $p): bool
    {
        return $p['hand'] !== [] && self::pending($p) === [];
    }

    /** @param array<string,mixed> $s */
    public static function current(array $s): int
    {
        return $s['turnOrder'][$s['turnPos']];
    }

    /** @param array<string,mixed> $s */
    private static function requireTurn(array $s, int $pi, array $phases = ['playerTurn']): void
    {
        if (!in_array($s['phase'], $phases, true) || self::current($s) !== $pi) {
            throw ApiError::conflict('It is not your turn', 'not_your_turn');
        }
    }

    // --------------------------------------------------------- break draw

    /** @param array<string,mixed> $s */
    public static function pickBreak(array &$s, int $pi, int $index, int $nowMs): void
    {
        // A repeated pick can arrive after the last card settled the break.
        if ($s['players'][$pi]['breakCard'] !== null) {
            throw ApiError::conflict('You already picked', 'already_picked');
        }
        if ($s['phase'] !== 'determiningBreak') {
            throw ApiError::conflict('The break is already decided', 'wrong_phase');
        }
        if ($index < 0 || $index >= self::SPREAD || $s['breakSpread'][$index] === null) {
            throw ApiError::conflict('That card is taken', 'card_taken');
        }
        $s['players'][$pi]['breakCard'] = $s['breakSpread'][$index];
        $s['breakSpread'][$index] = null;
        $s['players'][$pi]['missed'] = 0;
        self::maybeStart($s, $nowMs);
    }

    /** Once everybody holds a break card: fix the order and deal. @param array<string,mixed> $s */
    private static function maybeStart(array &$s, int $nowMs): void
    {
        foreach ($s['players'] as $p) {
            if ($p['breakCard'] === null) {
                return;
            }
        }
        $order = array_keys($s['players']);
        usort($order, static fn (int $a, int $b): int => $s['players'][$b]['breakCard'] <=> $s['players'][$a]['breakCard']);
        $s['turnOrder'] = $order;
        $s['turnPos'] = 0;

        $deck = self::shuffledDeck();
        for ($round = 0; $round < self::CARDS_PER_PLAYER; $round++) {
            foreach ($order as $idx) {
                $s['players'][$idx]['hand'][] = [
                    'k' => $s['nextKey']++, 'id' => array_pop($deck),
                    'completed' => false, 'revealed' => false, 'penalty' => false,
                ];
            }
        }
        $s['deck'] = $deck;
        $s['phase'] = 'playerTurn';
        // Clients play the reveal and the deal before the first shot clock runs.
        $s['deadline'] = $nowMs + 8000 + $s['shotSeconds'] * 1000;
    }

    // ---------------------------------------------------------- selection

    /** @param array<string,mixed> $s */
    public static function selectCard(array &$s, int $pi, int $cardId): void
    {
        self::requireTurn($s, $pi);
        if ($s['isBreakShot']) {
            throw ApiError::conflict('The break needs no card', 'break_shot');
        }
        $p = $s['players'][$pi];
        foreach ($p['hand'] as $c) {
            if ($c['id'] === $cardId && !$c['completed'] && in_array(self::ball($cardId), self::pending($p), true)) {
                $s['selectedCard'] = $cardId;
                $s['selectedFreeBall'] = null;
                return;
            }
        }
        throw ApiError::conflict('That card cannot be played', 'bad_card');
    }

    /** @param array<string,mixed> $s */
    public static function selectFreeBall(array &$s, int $pi, int $ball): void
    {
        self::requireTurn($s, $pi);
        if ($s['isBreakShot'] || !in_array($ball, self::FREE_BALLS, true)) {
            throw ApiError::conflict('That ball cannot be nominated', 'bad_ball');
        }
        $s['selectedCard'] = null;
        $s['selectedFreeBall'] = $ball;
    }

    /** @param array<string,mixed> $s */
    public static function targetBall(array $s): ?int
    {
        return $s['selectedCard'] !== null ? self::ball($s['selectedCard']) : $s['selectedFreeBall'];
    }

    // --------------------------------------------------------------- shot

    /** @param array<string,mixed> $s @param array<string,mixed> $params */
    public static function shoot(array &$s, int $pi, array $params, int $nowMs): void
    {
        self::requireTurn($s, $pi);
        if (!$s['isBreakShot'] && self::targetBall($s) === null) {
            throw ApiError::conflict('Reveal a card first', 'no_target');
        }
        $s['shot'] = ['seq' => ++$s['shotSeq'], 'by' => $pi] + $params;
        $s['phase'] = 'shooting';
        $s['players'][$pi]['missed'] = 0;
        $s['deadline'] = $nowMs + 25000;
    }

    /**
     * @param array<string,mixed> $s
     * @param array{firstContact:?int,pocketed:list<int>,cuePocketed:bool,railContact:bool} $o
     */
    public static function resolve(array &$s, int $pi, array $o, int $nowMs): void
    {
        self::requireTurn($s, $pi, ['shooting']);
        $p = &$s['players'][$pi];
        $wasBreak = $s['isBreakShot'];
        $selected = $s['selectedCard'];
        $target = self::targetBall($s);
        $required = self::required($p);
        $p['stats']['shots']++;
        $s['shotNumber']++;

        $foul = 'none';
        $penaltyCount = 0;
        if (!$wasBreak) {
            if ($o['firstContact'] === null) {
                $foul = 'noContact';
                $penaltyCount = 1;
            } elseif ($o['firstContact'] !== $target) {
                $foul = 'wrongFirstContact';
                $penaltyCount = 1;
            }
            foreach ($o['pocketed'] as $b) {
                if (!in_array($b, self::FREE_BALLS, true) && !in_array($b, $required, true)) {
                    $foul = 'wrongBallPocketed';
                    $penaltyCount = 2;
                    break;
                }
            }
        }
        if ($o['cuePocketed'] && $foul === 'none') {
            $foul = 'scratch';
        }

        $completed = [];
        $shown = [];
        $earned = 0;
        $continues = false;
        $becameReady = false;
        $penalties = 0;
        if ($foul === 'none') {
            foreach ($o['pocketed'] as $b) {
                if (in_array($b, self::FREE_BALLS, true)) {
                    $earned++;
                } elseif (in_array($b, self::pending($p), true)) {
                    $completed[] = $b;
                    $shown[] = self::completeObjective($p, $b, $selected);
                }
            }
            $p['stats']['ballsCompleted'] += count($completed);
            $p['stats']['extraShots'] += $earned;
            $s['extraShots'] += $earned;
            if (self::ready($p)) {
                $becameReady = true;
            } elseif ($completed !== []) {
                $continues = true;
            } elseif ($s['extraShots'] > 0) {
                $s['extraShots']--;
                $continues = true;
            }
        } else {
            $p['stats']['fouls']++;
            $penalties = self::drawPenalties($s, $pi, $penaltyCount);
        }
        unset($p);

        $s['isBreakShot'] = false;
        $s['selectedCard'] = null;
        $s['selectedFreeBall'] = null;
        $s['ballInHand'] = $o['cuePocketed'];
        $s['shot'] = null;
        if ($continues) {
            $s['phase'] = 'playerTurn';
        } else {
            self::advance($s);
        }
        $s['deadline'] = $nowMs + 3500 + $s['shotSeconds'] * 1000;
        $s['lastResult'] = [
            'seq' => ++$s['resultSeq'], 'playerIndex' => $pi, 'selectedCard' => $selected, 'selectedBall' => $target,
            'firstContactBall' => $o['firstContact'], 'pocketedBalls' => $o['pocketed'],
            'cueBallPocketed' => $o['cuePocketed'], 'legal' => $foul === 'none', 'foulType' => $foul,
            'completedObjectives' => $completed, 'shownCards' => $shown, 'earnedExtraShots' => $earned,
            'penaltyCount' => $penalties, 'turnContinues' => $continues,
            'nextPlayer' => $s['winner'] === null ? self::current($s) : $pi,
            'becameReadyToDeclare' => $becameReady, 'wasBreak' => $wasBreak,
        ];
    }

    /** Grays exactly one card for $ball: the revealed one if it matches, else a random equivalent. */
    private static function completeObjective(array &$p, int $ball, ?int $selected): int
    {
        $p['completedBalls'][] = $ball;
        $options = [];
        foreach ($p['hand'] as $i => $c) {
            if (self::ball($c['id']) === $ball && !$c['completed']) {
                if ($c['id'] === $selected) {
                    $options = [$i];
                    break;
                }
                $options[] = $i;
            }
        }
        $i = $options[random_int(0, count($options) - 1)];
        $p['hand'][$i]['completed'] = true;
        $p['hand'][$i]['revealed'] = true;
        return $p['hand'][$i]['id'];
    }

    /** Penalty cards are real objectives: an already completed rank is re-opened. */
    private static function drawPenalties(array &$s, int $pi, int $count): int
    {
        $drawn = 0;
        for ($i = 0; $i < $count && $s['deck'] !== []; $i++) {
            $card = array_pop($s['deck']);
            $s['players'][$pi]['hand'][] = [
                'k' => $s['nextKey']++, 'id' => $card, 'completed' => false, 'revealed' => false, 'penalty' => true,
            ];
            $s['players'][$pi]['completedBalls'] = array_values(
                array_diff($s['players'][$pi]['completedBalls'], [self::ball($card)])
            );
            $drawn++;
        }
        $s['players'][$pi]['stats']['penaltyCards'] += $drawn;
        return $drawn;
    }

    /** Next player still in the game; the last one standing wins. */
    private static function advance(array &$s): void
    {
        $n = count($s['turnOrder']);
        $in = array_values(array_filter($s['turnOrder'], static fn (int $i): bool => !$s['players'][$i]['out']));
        if (count($in) <= 1) {
            $s['winner'] = $in[0] ?? self::current($s);
            $s['phase'] = 'gameOver';
            return;
        }
        do {
            $s['turnPos'] = ($s['turnPos'] + 1) % $n;
        } while ($s['players'][self::current($s)]['out']);
        $s['extraShots'] = 0;
        $s['phase'] = self::ready($s['players'][self::current($s)]) ? 'declarePhase' : 'playerTurn';
    }

    // ------------------------------------------------------------ timeout

    /** Applies whatever is overdue. Returns true if the state changed. @param array<string,mixed> $s */
    public static function tick(array &$s, int $nowMs): bool
    {
        if ($s['phase'] === 'gameOver' || $nowMs <= $s['deadline'] + 1500) {
            return false;
        }
        if ($s['phase'] === 'determiningBreak') {
            // Anyone who has not picked gets a random card from what is left.
            foreach ($s['players'] as $pi => $p) {
                if ($p['breakCard'] === null) {
                    $free = array_keys(array_filter($s['breakSpread'], static fn ($c) => $c !== null));
                    $index = $free[random_int(0, count($free) - 1)];
                    $s['players'][$pi]['breakCard'] = $s['breakSpread'][$index];
                    $s['breakSpread'][$index] = null;
                }
            }
            self::maybeStart($s, $nowMs);
            return true;
        }
        self::timeout($s, $nowMs);
        return true;
    }

    /** Shot clock ran out: one penalty card, the turn passes. Three in a row forfeit. */
    private static function timeout(array &$s, int $nowMs): void
    {
        $pi = self::current($s);
        $s['players'][$pi]['stats']['timeouts']++;
        $s['players'][$pi]['stats']['fouls']++;
        $s['players'][$pi]['missed']++;
        $penalties = self::drawPenalties($s, $pi, 1);
        $selected = $s['selectedCard'];
        $target = self::targetBall($s);
        $s['selectedCard'] = null;
        $s['selectedFreeBall'] = null;
        $s['shot'] = null;
        if ($s['players'][$pi]['missed'] >= 3) {
            $s['players'][$pi]['out'] = true;
        }
        self::advance($s);
        $s['deadline'] = $nowMs + 3500 + $s['shotSeconds'] * 1000;
        $s['lastResult'] = [
            'seq' => ++$s['resultSeq'], 'playerIndex' => $pi, 'selectedCard' => $selected, 'selectedBall' => $target,
            'firstContactBall' => null, 'pocketedBalls' => [], 'cueBallPocketed' => false, 'legal' => false,
            'foulType' => 'timeout', 'completedObjectives' => [], 'shownCards' => [], 'earnedExtraShots' => 0,
            'penaltyCount' => $penalties, 'turnContinues' => false,
            'nextPlayer' => $s['winner'] === null ? self::current($s) : $pi,
            'becameReadyToDeclare' => false, 'wasBreak' => false,
        ];
    }

    // ------------------------------------------------------------ declare

    /** @param array<string,mixed> $s */
    public static function declareWinner(array &$s, int $pi): void
    {
        self::requireTurn($s, $pi, ['declarePhase']);
        if ($s['winner'] !== null || !self::ready($s['players'][$pi])) {
            throw ApiError::conflict('You cannot declare now', 'cannot_declare');
        }
        $s['winner'] = $pi;
        $s['phase'] = 'gameOver';
    }

    /** A player leaves for good. @param array<string,mixed> $s */
    public static function forfeit(array &$s, int $pi, int $nowMs): void
    {
        if ($s['phase'] === 'gameOver' || $s['players'][$pi]['out']) {
            return;
        }
        $s['players'][$pi]['out'] = true;
        if ($s['phase'] === 'determiningBreak') {
            $in = array_keys(array_filter($s['players'], static fn ($p) => !$p['out']));
            if (count($in) <= 1) {
                $s['winner'] = $in[0] ?? $pi;
                $s['phase'] = 'gameOver';
            }
            return;
        }
        $wasCurrent = self::current($s) === $pi;
        $in = array_filter($s['turnOrder'], static fn (int $i): bool => !$s['players'][$i]['out']);
        if (count($in) <= 1 || $wasCurrent) {
            $s['selectedCard'] = null;
            $s['selectedFreeBall'] = null;
            $s['shot'] = null;
            self::advance($s);
            $s['deadline'] = $nowMs + 2000 + $s['shotSeconds'] * 1000;
        }
    }

    // --------------------------------------------------------------- view

    /** What player $pi may see. Hidden: other hands, the deck, unrevealed break cards. */
    public static function view(array $s, int $pi): array
    {
        $allPicked = $s['turnOrder'] !== [];
        $over = $s['phase'] === 'gameOver';
        $players = [];
        foreach ($s['players'] as $i => $p) {
            $hand = [];
            foreach ($p['hand'] as $c) {
                $visible = $i === $pi || $c['revealed'] || $c['id'] === $s['selectedCard'] || $over;
                $hand[] = ['k' => $c['k'], 'id' => $visible ? $c['id'] : null,
                    'completed' => $c['completed'], 'revealed' => $c['revealed'], 'penalty' => $c['penalty']];
            }
            $players[] = [
                'uid' => $p['uid'], 'name' => $p['name'], 'avatar' => $p['avatar'], 'cue' => $p['cue'] ?? 'classic', 'out' => $p['out'],
                'picked' => $p['breakCard'] !== null,
                'breakCard' => $allPicked ? $p['breakCard'] : null,
                'hand' => $hand, 'completedBalls' => array_values($p['completedBalls']),
                'ready' => self::ready($p),
                'pending' => ($i === $pi || $over) ? count(self::pending($p)) : null,
                'stats' => $p['stats'],
            ];
        }
        return [
            'kind' => 'poker', 'phase' => $s['phase'], 'you' => $pi, 'players' => $players, 'bet' => $s['bet'] ?? null,
            'breakSpread' => array_map(static fn ($c) => $c !== null, $s['breakSpread']),
            'turnOrder' => $s['turnOrder'], 'turnPos' => $s['turnPos'],
            'isBreakShot' => $s['isBreakShot'], 'ballInHand' => $s['ballInHand'], 'extraShots' => $s['extraShots'],
            'selectedCard' => $s['selectedCard'], 'selectedFreeBall' => $s['selectedFreeBall'],
            'shotNumber' => $s['shotNumber'], 'winner' => $s['winner'], 'lastResult' => $s['lastResult'],
            'rackOrder' => $s['rackOrder'], 'balls' => $s['balls'], 'lastShot' => $s['lastShot'],
            'deckCount' => count($s['deck']), 'shotSeconds' => $s['shotSeconds'], 'deadline' => $s['deadline'],
        ];
    }
}
