<?php
declare(strict_types=1);

// Rule-engine checks that need a controlled clock (no server, no database):
//   php tests/engine_test.php
require dirname(__DIR__) . '/src/bootstrap.php';

use App\Game\PokerEngine;
use App\Game\PoolEngine;

$passed = 0;
function check(bool $ok, string $what): void
{
    global $passed;
    if (!$ok) {
        fwrite(STDERR, "FAIL: $what\n");
        exit(1);
    }
    $passed++;
}

$players = static fn (int $n): array => array_map(
    static fn (int $i): array => ['uid' => $i + 1, 'name' => "P$i", 'avatar' => 'asset:avatar_1'],
    range(0, $n - 1)
);
$t0 = 1_000_000;

// ---------------------------------------------------------------- poker
$s = PokerEngine::newState($players(4), 30, $t0);
check(!PokerEngine::tick($s, $t0 + 10_000), 'nothing is overdue during the break draw');
PokerEngine::pickBreak($s, 2, 0, $t0 + 1000);
check(PokerEngine::tick($s, $t0 + 40_000), 'break draw deadline passes');
check($s['phase'] === 'playerTurn' && count($s['turnOrder']) === 4, 'missing picks are made for absent players and the cards are dealt');
foreach ($s['players'] as $p) {
    check(count($p['hand']) === 7, 'everyone holds 7 cards');
}
$ids = array_merge(...array_map(static fn ($p) => array_column($p['hand'], 'id'), $s['players']));
check(count(array_unique(array_merge($ids, $s['deck']))) === 52, 'hands and penalty pile are one full deck');

$first = PokerEngine::current($s);
$now = $s['deadline'] - 1;
check(!PokerEngine::tick($s, $now), 'no timeout before the deadline');
$now = $s['deadline'] + 2000;
check(PokerEngine::tick($s, $now), 'shot clock expires');
check(count($s['players'][$first]['hand']) === 8 && $s['players'][$first]['hand'][7]['penalty'], 'timeout: +1 penalty card');
check(PokerEngine::current($s) !== $first && $s['lastResult']['foulType'] === 'timeout', 'timeout: turn passes');
check($s['isBreakShot'], 'the break is still to be played');


// Three timeouts in a row put a player out; the last one standing wins.
$s = PokerEngine::newState($players(4), 30, $t0);
foreach ([0, 1, 2, 3] as $i) {
    PokerEngine::pickBreak($s, $i, $i, $t0);
}
$guard = 0;
while ($s['phase'] !== 'gameOver' && $guard++ < 40) {
    PokerEngine::tick($s, $s['deadline'] + 2000);
}
check($s['phase'] === 'gameOver' && $s['winner'] !== null, 'a table of absent players ends');
check(count(array_filter($s['players'], static fn ($p) => $p['out'])) === 3, 'three players timed out of the game');

// Ready player must wait; a penalty card of a finished rank re-opens it.
$s = PokerEngine::newState($players(4), 30, $t0);
foreach ([0, 1, 2, 3] as $i) {
    PokerEngine::pickBreak($s, $i, $i, $t0);
}
$pi = PokerEngine::current($s);
$s['isBreakShot'] = false;
$s['players'][$pi]['hand'] = [
    ['k' => 100, 'id' => 0, 'completed' => false, 'revealed' => false, 'penalty' => false], // A clubs
    ['k' => 101, 'id' => 1, 'completed' => false, 'revealed' => false, 'penalty' => false], // A diamonds
];
check(PokerEngine::required($s['players'][$pi]) === [1], 'duplicate ranks are one objective');
PokerEngine::selectCard($s, $pi, 1, );
PokerEngine::shoot($s, $pi, [], $t0);
PokerEngine::resolve($s, $pi, ['firstContact' => 1, 'pocketed' => [1], 'cuePocketed' => false, 'railContact' => true], $t0);
$grey = array_filter($s['players'][$pi]['hand'], static fn ($c) => $c['completed']);
check(count($grey) === 1 && array_values($grey)[0]['id'] === 1, 'only the revealed card grays');
check($s['lastResult']['becameReadyToDeclare'] && $s['winner'] === null && PokerEngine::current($s) !== $pi, 'ready, turn ends, no win yet');
$s['deck'] = [2]; // A hearts on top of the penalty pile
$s['turnPos'] = array_search($pi, $s['turnOrder'], true);
$s['phase'] = 'declarePhase';
$s['deadline'] = $t0;
PokerEngine::tick($s, $t0 + 5000);
check(!PokerEngine::ready($s['players'][$pi]) && PokerEngine::pending($s['players'][$pi]) === [1], 'timing out in the declare phase re-opens the objective');

// ----------------------------------------------------------------- pool
$s = PoolEngine::newState('nine', $players(2), 30, $t0);
$me = $s['turn'];
check(PoolEngine::tick($s, $s['deadline'] + 2000), '9-ball: clock expires');
check($s['turn'] === 1 - $me && $s['ballInHand'] && $s['isBreakShot'] && $s['behindHeadString'], 'timeout on the break: opponent breaks, ball in hand behind the line');
check($s['players'][$me]['consecutiveFouls'] === 1, 'a timeout counts as a foul');
$s['players'][$s['turn']]['consecutiveFouls'] = 2;
$loser = $s['turn'];
PoolEngine::tick($s, $s['deadline'] + 2000);
check($s['phase'] === 'gameOver' && $s['winner'] === 1 - $loser && $s['winReason'] === 'THREE FOULS IN A ROW', '9-ball: third foul in a row loses');

$s = PoolEngine::newState('eight', $players(2), 30, $t0);
for ($i = 0; $i < 6 && $s['phase'] !== 'gameOver'; $i++) {
    PoolEngine::tick($s, $s['deadline'] + 2000);
}
check($s['phase'] === 'gameOver' && $s['winReason'] === 'OPPONENT LEFT THE GAME', '8-ball: three missed turns forfeit');

$s = PoolEngine::newState('eight', $players(2), 30, $t0);
$me = $s['turn'];
PoolEngine::shoot($s, $me, [], $t0);
PoolEngine::resolve($s, $me, ['firstContact' => 3, 'pocketed' => [8, 77], 'cuePocketed' => false,
    'railAfterContact' => true, 'objectBallsToRail' => 4, 'pocketOf' => [8 => 1]], $t0);
check($s['winner'] === null && in_array(8, $s['onTable'], true) && $s['lastResult']['pocketed'] === [8], '8 on the break is spotted; a ball that is not on the table is ignored');

echo "OK - $passed checks passed\n";
