<?php
declare(strict_types=1);

// Plays the strokes given as JSON ([[seat, x, dirX, dirY, power], ...]) on the
// opening layout and prints, per stroke, [pocketed, strikerPocketed, discs].
// test/carrom_test.dart runs the same strokes in Dart and compares.

require dirname(__DIR__) . '/src/bootstrap.php';

use App\Game\CarromPhysics;

$shots = json_decode($argv[1] ?? '[]', true);
$w = CarromPhysics::fromState(CarromPhysics::opening());
$out = [];
foreach ($shots as [$seat, $x, $dirX, $dirY, $power]) {
    $w->placeStriker((int) $seat, (float) $x);
    $w->shoot((float) $dirX, (float) $dirY, (float) $power);
    $w->simulate();
    $out[] = [$w->pocketed, $w->strikerPocketed, $w->toState()];
    $w->gone[CarromPhysics::STRIKER] = true;
    foreach ($w->pocketed as $d) {
        $w->returnToCentre($d);
    }
}
echo json_encode($out, JSON_PRESERVE_ZERO_FRACTION);
