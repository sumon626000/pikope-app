<?php
declare(strict_types=1);

// End-to-end check of the API against a running server:
//   php tests/api_flow.php http://127.0.0.1:8080
// The server must run with APP_TEST_HOOKS=1 (never in production): most shots
// here are scripted outcomes so every ruling can be reached on purpose; a few
// are real strokes simulated by the server.

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
    $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    return [$status, json_decode((string) $raw, true) ?? ['raw' => $raw]];
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

function guest(string $name): array
{
    [$status, $r] = call('POST', '/auth/guest', null, ['displayName' => $name]);
    check($status === 200 && isset($r['token']), "guest $name");
    return [$r['token'], $r['user']['id']];
}

function act(string $token, int $gameId, array $body): array
{
    return call('POST', "/games/$gameId/actions", $token, $body);
}

function state(string $token, int $gameId): array
{
    [$status, $r] = call('GET', "/games/$gameId?since=0", $token);
    check($status === 200, 'poll game');
    return $r['state'];
}

/** Plays a scripted outcome for the player whose turn it is (server test hook). */
function shot(string $token, int $gameId, array $outcome): array
{
    [$st, $r] = act($token, $gameId, ['type' => 'test_shot'] + $outcome
        + ['firstContact' => null, 'pocketed' => [], 'cuePocketed' => false, 'railAfterContact' => true, 'objectBallsToRail' => 4]);
    check($st === 200, 'shot accepted: ' . json_encode($r));
    return $r['state'];
}

/** A real stroke, simulated by the server. */
function stroke(string $token, int $gameId, array $extra = []): array
{
    return act($token, $gameId, $extra + ['type' => 'shoot', 'dirX' => 1.0, 'dirY' => 0.0, 'power' => 0.9,
        'spinX' => 0, 'spinY' => 0, 'cueX' => 250, 'cueY' => 250]);
}

// ------------------------------------------------------------------ misc
[$st, $r] = call('GET', '/health');
check($st === 200 && $r['ok'] === true, 'health');
[$st, $r] = call('GET', '/config');
check($st === 200 && array_key_exists('ws', $r), 'config tells the app where live play is');
[$st] = call('GET', '/me');
check($st === 401, 'me requires a token');
[$st] = call('GET', '/me', 'not-a-token');
check($st === 401, 'bad token rejected');
[$st] = call('GET', '/nope');
check($st === 404, 'unknown route');

// --------------------------------------------------- accounts and profile
$phoneLocal = '17' . str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT);
[$gt] = guest('Upgrader');
[$st, $r] = call('POST', '/auth/register', $gt, ['phone' => $phoneLocal, 'password' => 'short']);
check($st === 400 && $r['error'] === 'weak_password', 'weak password refused');
[$st, $r] = call('POST', '/auth/register', $gt, ['phone' => $phoneLocal, 'password' => 'correct horse']);
check($st === 200 && $r['user']['isGuest'] === false && $r['user']['phone'] === '+880 ' . $phoneLocal, 'guest upgraded to an account');
[$st, $r] = call('POST', '/auth/register', null, ['phone' => $phoneLocal, 'password' => 'another pass']);
check($st === 409 && $r['error'] === 'phone_taken', 'duplicate phone refused');
[$st, $r] = call('POST', '/auth/login', null, ['phone' => $phoneLocal, 'password' => 'wrong password']);
check($st === 401, 'wrong password refused');
[$st, $r] = call('POST', '/auth/login', null, ['phone' => $phoneLocal, 'password' => 'correct horse']);
check($st === 200 && isset($r['token']), 'login works');
$token = $r['token'];
[$st, $r] = call('PATCH', '/me', $token, ['displayName' => "Rob'); DROP--", 'avatar' => 'asset:avatar_3', 'tableSkin' => 'pro_green']);
check($st === 400 && $r['error'] === 'bad_name', 'nickname with special characters refused');
[$st, $r] = call('PATCH', '/me', $token, ['displayName' => 'Rob_9ball', 'avatar' => 'asset:avatar_3', 'tableSkin' => 'pro_green']);
check($st === 200 && $r['user']['displayName'] === 'Rob_9ball' && $r['user']['avatar'] === 'asset:avatar_3' && $r['user']['nameSet'] === true, 'profile updated');
[$st, $r] = call('PATCH', '/me', $token, ['avatar' => 'url:https://evil.example/x.png']);
check($st === 400, 'foreign avatar URL refused');
[$st, $r] = call('POST', '/matches/bot', $token, ['game' => 'nine', 'won' => true]);
check($st === 200 && $r['coins'] === 0 && $r['user']['xp'] === 10 && $r['user']['coins'] === 2000, 'practice match pays experience, not coins');
[$st, $r] = call('POST', '/matches/bot', $token, ['game' => 'nine', 'won' => true]);
check($st === 200 && $r['user']['xp'] === 10, 'practice farming limited');
[$st] = call('POST', '/auth/logout', $token);
[$st2] = call('GET', '/me', $token);
check($st === 200 && $st2 === 401, 'logout revokes the token');

// --------------------------------------------------------- password reset
$smsLog = $argv[2] ?? '';
if ($smsLog !== '') {
    @unlink($smsLog);
    [$st, $r] = call('POST', '/auth/forgot', null, ['phone' => '1800000000']);
    check($st === 200 && $r['ok'] === true && !is_file($smsLog), 'unknown phone: same answer, no SMS file');
    [$st, $r] = call('POST', '/auth/forgot', null, ['phone' => $phoneLocal]);
    check($st === 200 && is_file($smsLog), 'reset SMS logged');
    preg_match('/OTP code is (\d{6})/', file_get_contents($smsLog), $m);
    $code = $m[1];
    [$st, $r] = call('POST', '/auth/reset', null, ['phone' => $phoneLocal, 'code' => $code === '000000' ? '111111' : '000000', 'password' => 'brand new pass']);
    check($st === 400 && $r['error'] === 'bad_code', 'wrong reset code refused');
    [$st, $r] = call('POST', '/auth/login', null, ['phone' => $phoneLocal, 'password' => 'correct horse']);
    check($st === 200, 'old password still works until the reset completes');
    $oldToken = $r['token'];
    [$st, $r] = call('POST', '/auth/reset', null, ['phone' => $phoneLocal, 'code' => $code, 'password' => 'brand new pass']);
    check($st === 200 && isset($r['token']), 'password reset with the SMS code');
    [$st] = call('GET', '/me', $oldToken);
    check($st === 401, 'reset signs out every old session');
    [$st] = call('POST', '/auth/login', null, ['phone' => $phoneLocal, 'password' => 'correct horse']);
    [$st2] = call('POST', '/auth/login', null, ['phone' => $phoneLocal, 'password' => 'brand new pass']);
    check($st === 401 && $st2 === 200, 'only the new password works');
    [$st, $r] = call('POST', '/auth/reset', null, ['phone' => $phoneLocal, 'code' => $code, 'password' => 'yet another one']);
    check($st === 400, 'a reset code works once');
}

// --------------------------------------------------------- rooms: codes
[$a, $aId] = guest('<script>x');
[$b, $bId] = guest('Bob');
[$st, $room] = call('POST', '/rooms', $a, ['game' => 'nine', 'private' => true]);
check($st === 200 && $room['status'] === 'waiting' && strlen($room['code']) === 6, 'private room created');
[$st] = call('GET', "/rooms/{$room['id']}", $b);
check($st === 403, 'outsider cannot read a room');
[$st, $r] = call('POST', '/rooms/join', $b, ['code' => 'ZZZZZZ']);
check($st === 404, 'wrong code');
[$st, $r] = call('POST', '/rooms/join', $b, ['code' => strtolower($room['code'])]);
check($st === 200 && $r['status'] === 'playing' && $r['gameId'] !== null, 'second player starts the 9-ball game');
$gameId = $r['gameId'];
[$c] = guest('Cat');
[$st] = call('GET', "/games/$gameId", $c);
check($st === 403, 'outsider cannot read a game');
[$st, $r] = call('POST', '/rooms/join', $c, ['code' => $room['code']]);
check($st === 409, 'cannot join a started room');

// ------------------------------------------------------------- 9-ball
$tokens = [$a, $b];
$s = state($a, $gameId);
check($s['kind'] === 'nine' && $s['isBreakShot'] && count($s['rackOrder']) === 9 && $s['rackOrder'][0] === 1 && $s['rackOrder'][4] === 9, '9-ball rack: 1 in front, 9 in the middle');
$turn = $s['turn'];
[$st, $r] = stroke($tokens[1 - $turn], $gameId);
check($st === 409 && $r['error'] === 'not_your_turn', 'cannot shoot out of turn');
check(count($s['balls']) === 16 && $s['balls'][0] === [250, 250, false] && $s['balls'][1][0] === 750, 'the server racked the table: cue on the head spot, 1 on the foot spot');
$s = shot($tokens[$turn], $gameId, ['firstContact' => 1, 'pocketed' => [3]]);
check($s['turn'] === $turn && $s['pushOutAvailable'] && $s['lastResult']['turnContinues'], 'legal break with a ball down keeps the table; push out offered');
check($s['onTable'] === [1, 2, 4, 5, 6, 7, 8, 9], 'server tracks which balls are on the table');
[$st, $r] = act($tokens[$turn], $gameId, ['type' => 'push_out']);
check($st === 200 && $r['state']['pushOutDeclared'], 'push out declared');
$s = shot($tokens[$turn], $gameId, ['firstContact' => null]);
check($s['phase'] === 'pushOutChoice' && $s['turn'] === 1 - $turn && $s['lastResult']['foul'] === 'none', 'push out: no contact needed, opponent chooses');
[$st, $r] = act($tokens[1 - $turn], $gameId, ['type' => 'push_out_answer', 'shoot' => false]);
check($st === 200 && $r['state']['turn'] === $turn && $r['state']['phase'] === 'playerTurn', 'shot passed back');
$s = shot($tokens[$turn], $gameId, ['firstContact' => 4]);
check($s['lastResult']['foul'] === 'wrongBallFirst' && $s['ballInHand'] && $s['turn'] === 1 - $turn, 'wrong ball first: foul, ball in hand');
$s = shot($tokens[1 - $turn], $gameId, ['firstContact' => 1, 'pocketed' => [9], 'cuePocketed' => true]);
check($s['winner'] === null && $s['lastResult']['respot'] === [9] && in_array(9, $s['onTable'], true), '9 on a scratch is spotted, no win');
[$st, $r] = act($tokens[$turn], $gameId, ['type' => 'shot_result', 'seq' => 1, 'pocketed' => [9], 'firstContact' => 1]);
check($st === 400, 'clients can no longer report shot results');
[$st, $r] = stroke($tokens[$turn], $gameId, ['dirX' => 0.5, 'dirY' => 0.5]);
check($st === 400, 'aim must be a unit vector');
$s = shot($tokens[$turn], $gameId, ['firstContact' => 1, 'pocketed' => [9]]);
check($s['phase'] === 'gameOver' && $s['winner'] === $turn && $s['winReason'] === '9-BALL POCKETED', '9 by combination wins');
[$st, $me] = call('GET', '/me', $tokens[$turn]);
[$st, $them] = call('GET', '/me', $tokens[1 - $turn]);
check($me['user']['wins'] === 1 && $me['user']['coins'] === 2000 && $them['user']['coins'] === 2000 && $them['user']['games'] === 1
    && $me['user']['xp'] === 60 && $them['user']['xp'] === 20, 'friendly match: no coins move, counters and experience updated');
[$st, $r] = stroke($tokens[$turn], $gameId);
check($st === 200 && $r['state']['phase'] === 'gameOver', 'a finished game no longer changes');

// ------------------------------------------------------------- 8-ball
[$st, $r1] = call('POST', '/rooms/quick', $a, ['game' => 'eight']);
[$st, $r2] = call('POST', '/rooms/quick', $b, ['game' => 'eight']);
check($r1['id'] === $r2['id'] && $r2['status'] === 'playing', 'quick match pairs two players');
$gameId = $r2['gameId'];
$s = state($a, $gameId);
check($s['rackOrder'][4] === 8 && count($s['rackOrder']) === 15, '8-ball rack: 8 in the centre');
$turn = $s['turn'];
$s = shot($tokens[$turn], $gameId, ['firstContact' => 5]);
check($s['turn'] === 1 - $turn && $s['players'][0]['group'] === 'none', 'dry break, table open');
$t = 1 - $turn;
$s = shot($tokens[$t], $gameId, ['firstContact' => 11, 'pocketed' => [11]]);
check($s['players'][$t]['group'] === 'stripes' && $s['players'][1 - $t]['group'] === 'solids' && $s['turn'] === $t, 'first pocketed ball assigns groups');
$s = shot($tokens[$t], $gameId, ['firstContact' => 3]);
check($s['lastResult']['foul'] === 'wrongBallFirst', 'must hit own group first');
$t = 1 - $t; // solids
$s = shot($tokens[$t], $gameId, ['firstContact' => 1, 'pocketed' => [1, 2, 3, 4, 5, 6, 7]]);
check($s['turn'] === $t, 'solids cleared');
[$st, $r] = stroke($tokens[$t], $gameId);
check($st === 409 && $r['error'] === 'no_call', 'the 8 needs a called pocket');
[$st, $r] = act($tokens[$t], $gameId, ['type' => 'call_pocket', 'pocket' => 2]);
check($st === 200 && $r['state']['calledPocket'] === 2, 'pocket called');
$s = shot($tokens[$t], $gameId, ['firstContact' => 8, 'pocketed' => [8], 'pocketOf' => ['8' => 4]]);
check($s['phase'] === 'gameOver' && $s['winner'] === 1 - $t && $s['winReason'] === '8-BALL IN THE WRONG POCKET', '8 in the wrong pocket loses');

// ------------------------------------------------------------ 10-ball
call('POST', '/rooms/quick', $a, ['game' => 'ten']);
[$st, $r2] = call('POST', '/rooms/quick', $b, ['game' => 'ten']);
$gameId = $r2['gameId'];
$s = state($a, $gameId);
check($s['rackOrder'][0] === 1 && $s['rackOrder'][4] === 10 && count($s['rackOrder']) === 10, '10-ball rack');
$turn = $s['turn'];
// A real break, simulated on the server.
[$st, $r] = stroke($tokens[$turn], $gameId, ['cueX' => 900, 'cueY' => 250]);
check($st === 200, 'break accepted: ' . json_encode($r));
$s = $r['state'];
check($s['lastShot']['cueX'] == 250 && $s['lastShot']['by'] === $turn, 'cue ball in hand is limited to behind the head string on the break');
check($s['lastShot']['outcome']['firstContact'] === 1 && $s['lastShot']['durationMs'] > 1000, 'the server simulated the break: the 1 was struck first');
$moved = 0;
foreach ($s['balls'] as $n => $ball) {
    check($ball[2] || ($ball[0] >= 0 && $ball[0] <= 1000 && $ball[1] >= 0 && $ball[1] <= 500), "ball $n rests on the table");
    $moved += ($n >= 1 && $n <= 10 && !$ball[2] && abs($ball[0] - 750) > 40) ? 1 : 0;
}
check($moved >= 4, 'the rack was scattered');
check(!$s['isBreakShot'] && $s['lastResult']['seq'] === 1, 'the server ruled on its own simulation');
if ($s['phase'] !== 'gameOver') {
    $turn = $s['turn'];
    $s = shot($tokens[$turn], $gameId, ['firstContact' => min($s['onTable']), 'pocketed' => [10], 'railAfterContact' => true]);
}
check($s['phase'] === 'gameOver' && $s['winner'] !== null, '10 pocketed legally wins');

// ------------------------------------------------------- Billiard Poker
$p = [guest('P0'), guest('P1'), guest('P2'), guest('P3')];
$tok = array_column($p, 0);
foreach ($tok as $i => $t) {
    [$st, $room] = call('POST', '/rooms/quick', $t, ['game' => 'poker']);
    check($st === 200 && $room['status'] === ($i < 3 ? 'waiting' : 'playing'), "poker seat $i");
}
$gameId = $room['gameId'];
$s = state($tok[0], $gameId);
check($s['phase'] === 'determiningBreak' && count($s['breakSpread']) === 30 && $s['players'][0]['breakCard'] === null, 'break draw open');
[$st, $r] = act($tok[0], $gameId, ['type' => 'pick_break', 'index' => 3]);
check($st === 200 && $r['state']['players'][0]['picked'] && $r['state']['players'][0]['breakCard'] === null && $r['state']['breakSpread'][3] === false, 'pick is hidden until everyone picked');
[$st, $r] = act($tok[1], $gameId, ['type' => 'pick_break', 'index' => 3]);
check($st === 409 && $r['error'] === 'card_taken', 'same break card refused');
[$st, $r] = act($tok[0], $gameId, ['type' => 'pick_break', 'index' => 5]);
check($st === 409 && $r['error'] === 'already_picked', 'second pick refused');
foreach ([1 => 7, 2 => 11, 3 => 20] as $i => $index) {
    [$st, $r] = act($tok[$i], $gameId, ['type' => 'pick_break', 'index' => $index]);
    check($st === 200, "pick $i");
}
$s = $r['state'];
check($s['phase'] === 'playerTurn' && count($s['turnOrder']) === 4 && $s['isBreakShot'], 'order set, cards dealt');
$cards = array_column($s['players'], 'breakCard');
$sorted = $s['turnOrder'];
for ($i = 0; $i < 3; $i++) {
    check($cards[$sorted[$i]] > $cards[$sorted[$i + 1]], 'turn order is descending break card');
}
// Hidden information: each client sees only its own hand.
$all = [];
foreach ($tok as $i => $t) {
    $v = state($t, $gameId);
    check(count($v['players'][$i]['hand']) === 7 && !in_array(null, array_column($v['players'][$i]['hand'], 'id'), true), "player $i sees own 7 cards");
    foreach ($v['players'] as $j => $other) {
        if ($j !== $i) {
            check(array_filter(array_column($other['hand'], 'id'), static fn ($id) => $id !== null) === [], "player $i cannot see hand $j");
            check($other['pending'] === null, 'opponents\' remaining count is hidden');
        }
    }
    check(!isset($v['deck']) && $v['deckCount'] === 24, 'deck is not sent');
    $all = array_merge($all, array_column($v['players'][$i]['hand'], 'id'));
}
check(count(array_unique($all)) === 28, 'no physical card dealt twice');

$hands = [];
foreach ($tok as $i => $t) {
    $hands[$i] = array_column(state($t, $gameId)['players'][$i]['hand'], 'id');
}
$ballOf = static fn (int $id): int => intdiv($id, 4) + 1;
$cur = static fn (array $s): int => $s['turnOrder'][$s['turnPos']];

$first = $cur($s);
[$st, $r] = act($tok[$first], $gameId, ['type' => 'select_card', 'cardId' => $hands[$first][0]]);
check($st === 409, 'no card on the break');
$s = shot($tok[$first], $gameId, ['firstContact' => 9]);
check(!$s['isBreakShot'] && $cur($s) !== $first && $s['lastResult']['legal'], 'open break, turn passes');

// Wrong first contact: +1 penalty card.
$pi = $cur($s);
[$st, $r] = stroke($tok[$pi], $gameId);
check($st === 409 && $r['error'] === 'no_target', 'shot needs a revealed card');
[$st, $r] = act($tok[$pi], $gameId, ['type' => 'select_card', 'cardId' => $hands[($pi + 1) % 4][0]]);
check($st === 409, 'cannot reveal someone else\'s card');
[$st, $r] = act($tok[$pi], $gameId, ['type' => 'select_card', 'cardId' => $hands[$pi][0]]);
check($st === 200 && $r['state']['selectedCard'] === $hands[$pi][0], 'card revealed');
$seen = state($tok[($pi + 1) % 4], $gameId);
check(in_array($hands[$pi][0], array_column($seen['players'][$pi]['hand'], 'id'), true), 'the revealed card is visible to everyone');
$target = $ballOf($hands[$pi][0]);
$s = shot($tok[$pi], $gameId, ['firstContact' => $target === 14 ? 15 : ($target % 13) + 1]);
check($s['lastResult']['foulType'] === 'wrongFirstContact' && $s['lastResult']['penaltyCount'] === 1 && count($s['players'][$pi]['hand']) === 8 && $cur($s) !== $pi, 'wrong first contact: +1 card, turn ends');

// Wrong ball pocketed: +2.
$pi = $cur($s);
$mine = array_map($ballOf, $hands[$pi]);
$foreign = current(array_filter(range(1, 13), static fn ($b) => !in_array($b, $mine, true)));
act($tok[$pi], $gameId, ['type' => 'select_card', 'cardId' => $hands[$pi][0]]);
$s = shot($tok[$pi], $gameId, ['firstContact' => $ballOf($hands[$pi][0]), 'pocketed' => [$foreign]]);
check($s['lastResult']['foulType'] === 'wrongBallPocketed' && $s['lastResult']['penaltyCount'] === 2 && count($s['players'][$pi]['hand']) === 9, 'wrong ball pocketed: +2 cards');

// Free ball: extra shot.
$pi = $cur($s);
[$st, $r] = act($tok[$pi], $gameId, ['type' => 'select_free', 'ball' => 14]);
check($st === 200 && $r['state']['selectedFreeBall'] === 14, 'free ball nominated without a card');
$s = shot($tok[$pi], $gameId, ['firstContact' => 14, 'pocketed' => [14]]);
check($s['lastResult']['earnedExtraShots'] === 1 && $s['lastResult']['turnContinues'] && $cur($s) === $pi, 'free ball: +1 extra shot');

// This player now clears every objective, one ball per shot.
$v = state($tok[$pi], $gameId);
$todo = array_values(array_unique(array_map($ballOf, array_column($v['players'][$pi]['hand'], 'id'))));
foreach ($todo as $n => $ball) {
    $v = state($tok[$pi], $gameId);
    $card = current(array_filter($v['players'][$pi]['hand'], static fn ($c) => $ballOf($c['id']) === $ball && !$c['completed']));
    [$st, $r] = act($tok[$pi], $gameId, ['type' => 'select_card', 'cardId' => $card['id']]);
    check($st === 200, "select ball $ball");
    $s = shot($tok[$pi], $gameId, ['firstContact' => $ball, 'pocketed' => [$ball]]);
    $grey = count(array_filter($s['players'][$pi]['hand'], static fn ($c) => $c['completed']));
    check($grey === $n + 1 && $s['lastResult']['shownCards'] === [$card['id']], "ball $ball: exactly one card grays, the revealed one");
}
check($s['lastResult']['becameReadyToDeclare'] && $s['winner'] === null && $s['players'][$pi]['ready'] && $cur($s) !== $pi, 'all done: ready, but no win yet');
[$st, $r] = act($tok[$pi], $gameId, ['type' => 'declare']);
check($st === 409, 'cannot declare outside the own turn');

// The other three miss; then the ready player's turn starts in the declare phase.
for ($k = 0; $k < 3; $k++) {
    $q = $cur($s);
    $v = state($tok[$q], $gameId);
    $card = current(array_filter($v['players'][$q]['hand'], static fn ($c) => !$c['completed']));
    act($tok[$q], $gameId, ['type' => 'select_card', 'cardId' => $card['id']]);
    $s = shot($tok[$q], $gameId, ['firstContact' => $ballOf($card['id'])]);
}
check($cur($s) === $pi && $s['phase'] === 'declarePhase', 'next scheduled turn opens the declare phase');
[$st, $r] = act($tok[($pi + 1) % 4], $gameId, ['type' => 'declare']);
check($st === 409, 'others cannot declare for them');
[$st, $r] = act($tok[$pi], $gameId, ['type' => 'declare']);
check($st === 200 && $r['state']['phase'] === 'gameOver' && $r['state']['winner'] === $pi, 'declare wins');
check(!in_array(null, array_column($r['state']['players'][($pi + 1) % 4]['hand'], 'id'), true), 'hands are shown once the game is over');
[$st, $lb] = call('GET', '/leaderboard', $tok[0]);
check($st === 200 && count($lb['entries']) > 0 && $lb['entries'][0]['wins'] >= 1, 'leaderboard lists winners');

// A four-player match survives players leaving; the last one standing wins.
$q = [guest('Q0'), guest('Q1'), guest('Q2'), guest('Q3')];
$qt = array_column($q, 0);
foreach ($qt as $t) {
    [$st, $qroom] = call('POST', '/rooms/quick', $t, ['game' => 'poker']);
}
$qg = $qroom['gameId'];
[$st, $r] = call('GET', '/me/active', $qt[2]);
check($st === 200 && $r['match']['gameId'] === $qg && $r['match']['game'] === 'poker' && count($r['match']['players']) === 4 && is_int($r['match']['seat']), 'a player can find the match they are in (rejoin)');
[$st, $r] = call('GET', '/me/active', $c);
check($st === 200 && $r['match'] === null, 'no active match for someone not playing');
foreach ([0 => 1, 1 => 2, 2 => 3, 3 => 4] as $i => $index) {
    act($qt[$i], $qg, ['type' => 'pick_break', 'index' => $index]);
}
$s = state($qt[0], $qg);
$leaver = $s['turnOrder'][0];
call('POST', "/rooms/{$qroom['id']}/leave", $qt[$leaver]);
$s = state($qt[($leaver + 1) % 4], $qg);
check($s['phase'] === 'playerTurn' && $s['players'][$leaver]['out'] && $s['turnOrder'][$s['turnPos']] !== $leaver && $s['winner'] === null, 'the player on turn leaves: play passes on, three remain');
[$st, $r] = call('GET', '/me/active', $qt[$leaver]);
check($r['match'] === null, 'whoever left has nothing to rejoin');
$next = $s['turnOrder'][$s['turnPos']];
[$st, $r] = stroke($qt[$next], $qg);
check($st === 200 && $r['state']['lastShot']['by'] === $next, 'the match goes on after someone left');
$left = [$leaver];
foreach ([1, 2] as $k) {
    $s = state($qt[$next], $qg);
    $other = current(array_filter([0, 1, 2, 3], static fn ($i) => !in_array($i, $left, true) && $i !== $next));
    call('POST', "/rooms/{$qroom['id']}/leave", $qt[$other]);
    $left[] = $other;
}
$s = state($qt[$next], $qg);
check($s['phase'] === 'gameOver' && $s['winner'] === $next, 'last player standing wins');

// Leaving a match hands the win to the opponent.
call('POST', '/rooms/quick', $a, ['game' => 'nine']);
[$st, $r2] = call('POST', '/rooms/quick', $b, ['game' => 'nine']);
[$st, $r] = call('POST', "/rooms/{$r2['id']}/leave", $a);
$s = state($b, $r2['gameId']);
check($s['phase'] === 'gameOver' && $s['winReason'] === 'OPPONENT LEFT THE GAME' && $s['players'][$s['winner']]['uid'] === $bId, 'leaving forfeits');

// Rematch: the same two players get a fresh private room.
[$st, $again] = call('POST', "/rooms/{$r2['id']}/rematch", $b);
check($st === 200 && $again['status'] === 'waiting' && $again['isPrivate'] && $again['id'] !== $r2['id'], 'rematch opens a new private room');
[$st, $r] = call('POST', "/rooms/{$r2['id']}/rematch", $c);
check($st === 403, 'only players of that match can rematch');
[$st, $again2] = call('POST', "/rooms/{$r2['id']}/rematch", $a);
check($st === 200 && $again2['id'] === $again['id'] && $again2['status'] === 'playing', 'the opponent lands in the same room and the match starts');

// Admin page and suspension.
$admin = static function (string $method, string $path, ?string $auth, array $post = []) use ($base): array {
    $ch = curl_init($base . $path);
    curl_setopt_array($ch, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true] + ($auth ? [CURLOPT_USERPWD => $auth] : [])
        + ($post ? [CURLOPT_POSTFIELDS => http_build_query($post)] : []));
    $body = (string) curl_exec($ch);
    return [curl_getinfo($ch, CURLINFO_HTTP_CODE), $body];
};
$adminAuth = $argv[3] ?? '';
if ($adminAuth !== '') {
    [$st] = $admin('GET', '/admin', null);
    check($st === 401, 'admin needs a login');
    [$st] = $admin('GET', '/admin', 'admin:wrong');
    check($st === 401, 'wrong admin password refused');
    [$st, $html] = $admin('GET', '/admin', $adminAuth);
    check($st === 200 && str_contains($html, 'Latest players') && str_contains($html, 'Latest matches'), 'admin page renders');
    check(!str_contains($html, '<script'), 'player names are escaped in the admin page');
    preg_match('/name="csrf" value="([0-9a-f]+)"/', $html, $m);
    [$st] = $admin('POST', '/admin/ban', $adminAuth, ['id' => $bId, 'banned' => 1, 'csrf' => 'nope']);
    check($st === 400, 'ban form needs its token');
    $admin('POST', '/admin/ban', $adminAuth, ['id' => $bId, 'banned' => 1, 'csrf' => $m[1]]);
    [$st, $r] = call('GET', '/me', $b);
    check($st === 401 || ($st === 403 && $r['error'] === 'banned'), 'a suspended player is locked out');
    $admin('POST', '/admin/ban', $adminAuth, ['id' => $bId, 'banned' => 0, 'csrf' => $m[1]]);
}

// ---- Challenges (1v1) ----------------------------------------------------
[$chA, $chAid] = guest('ChA');
[$chB, $chBid] = guest('ChB');
[$st, $r] = call('GET', '/challenge/online', $chA);
check($st === 200 && is_array($r['players']), 'online players listed');
[$st, $r] = call('POST', '/challenge/send', $chA, ['toUserId' => $chAid, 'game' => 'billiard', 'level' => 1]);
check($st === 400, 'cannot challenge yourself');
[$st, $ch] = call('POST', '/challenge/send', $chA, ['toUserId' => $chBid, 'game' => 'billiard', 'level' => 1]);
check($st === 200 && $ch['status'] === 'pending' && $ch['buyIn'] === 105, 'challenge sent');
$chId = $ch['id'];
[$st, $r] = call('GET', '/challenge/inbox', $chB);
check($st === 200 && count($r['incoming']) === 1 && $r['incoming'][0]['id'] === $chId, 'target sees the invite');
[$st, $r] = call('POST', "/challenge/$chId/accept", $chB);
check($st === 200 && $r['room']['status'] === 'playing' && $r['room']['gameId'] !== null, 'challenge accepted, match started');
[$st, $me] = call('GET', '/me', $chA);
[$st2, $you] = call('GET', '/me', $chB);
check($me['user']['coins'] === 1895 && $you['user']['coins'] === 1895, 'both buy-ins taken');
[$st, $r] = call('GET', '/challenge/inbox', $chA);
check($st === 200 && $r['outgoing'][0]['status'] === 'accepted' && $r['outgoing'][0]['roomId'] !== null, 'sender sees acceptance');
[$st, $r] = call('POST', '/challenge/send', $chA, ['toUserId' => $chBid, 'game' => 'billiard', 'level' => 0]);
check($st === 409 && $r['error'] === 'you_busy', 'cannot challenge while in a match');

echo "OK - $passed checks passed\n";
