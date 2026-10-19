<?php
declare(strict_types=1);

namespace App\Game;

/**
 * The pool table simulation, server side. A line-for-line port of the app's
 * lib/game/physics/physics_world.dart: same constants, same order of
 * floating-point operations, so a shot played here comes to rest exactly
 * where the app's own animation of it does. The server's result is the
 * authority; the apps only draw it.
 *
 * If you change one side, change the other and run the online tests - they
 * compare both simulations ball by ball.
 */
final class Physics
{
    public const R = 16.0;
    public const WIDTH = 1000.0;
    public const HEIGHT = 500.0;
    public const HEAD_STRING_X = 250.0;
    private const DT = 1 / 300;
    private const MAX_SPEED = 2600.0;
    private const MIN_SPEED = 160.0;
    private const SLIDE_DECEL = 22.0;
    private const DRAG = 0.46;
    private const REST_SPEED = 2;
    private const BALL_RESTITUTION = 0.96;
    private const CUSHION_RESTITUTION = 0.78;
    private const MAX_STEPS = 20000;

    /** Capture circles: centre x, centre y, radius. */
    private const POCKETS = [
        [-6.0, -6.0, 30.0], [500.0, -20.0, 24.0], [1006.0, -6.0, 30.0],
        [-6.0, 506.0, 30.0], [500.0, 520.0, 24.0], [1006.0, 506.0, 30.0],
    ];

    /** Cushion segments: ax, ay, bx, by, normal x, normal y. */
    private const CUSHIONS = [
        [38.0, 0.0, 470.0, 0.0, 0.0, 1.0], [530.0, 0.0, 962.0, 0.0, 0.0, 1.0],
        [38.0, 500.0, 470.0, 500.0, 0.0, -1.0], [530.0, 500.0, 962.0, 500.0, 0.0, -1.0],
        [0.0, 38.0, 0.0, 462.0, 1.0, 0.0], [1000.0, 38.0, 1000.0, 462.0, -1.0, 0.0],
    ];

    /** @var list<float> */
    private array $x = [];
    /** @var list<float> */
    private array $y = [];
    /** @var list<float> */
    private array $vx = [];
    /** @var list<float> */
    private array $vy = [];
    /** @var list<bool> */
    private array $gone = [];

    private ?int $firstContact = null;
    /** @var list<int> */
    private array $pocketed = [];
    private bool $cuePocketed = false;
    private bool $railContact = false;
    private bool $railAfterContact = false;
    /** @var array<int,true> */
    private array $railBalls = [];
    /** @var array<int,int> */
    private array $pocketOf = [];
    private float $spinX = 0.0;
    private float $spinY = 0.0;

    /** @param list<array{0:float|int,1:float|int,2:bool}> $balls 16 x [x, y, pocketed] */
    public static function fromState(array $balls): self
    {
        $w = new self();
        for ($i = 0; $i < 16; $i++) {
            $w->x[$i] = (float) $balls[$i][0];
            $w->y[$i] = (float) $balls[$i][1];
            $w->vx[$i] = 0.0;
            $w->vy[$i] = 0.0;
            $w->gone[$i] = (bool) $balls[$i][2];
        }
        return $w;
    }

    /** @return list<array{0:float,1:float,2:bool}> */
    public function toState(): array
    {
        $out = [];
        for ($i = 0; $i < 16; $i++) {
            $out[] = [$this->x[$i], $this->y[$i], $this->gone[$i]];
        }
        return $out;
    }

    /**
     * Cue ball on the head spot and $numbers racked row by row ($rows[r] balls
     * in row r) with the apex on the foot spot. Other balls stay off the table.
     * @param list<int> $rows @param list<int> $numbers
     * @return list<array{0:float,1:float,2:bool}>
     */
    public static function rack(array $rows, array $numbers): array
    {
        $balls = array_fill(0, 16, [0.0, 0.0, true]);
        $gap = 0.3;
        $dx = (2 * self::R + $gap) * sqrt(3) / 2;
        $dy = 2 * self::R + $gap;
        $k = 0;
        foreach ($rows as $row => $count) {
            for ($j = 0; $j < $count; $j++) {
                $balls[$numbers[$k++]] = [750.0 + $row * $dx, 250.0 + ($j - ($count - 1) / 2) * $dy, false];
            }
        }
        $balls[0] = [250.0, 250.0, false];
        return $balls;
    }

    private static function inside(float $x, float $y, float $margin): bool
    {
        return $x >= $margin && $x <= self::WIDTH - $margin && $y >= $margin && $y <= self::HEIGHT - $margin;
    }

    private function isFree(float $px, float $py, int $ignore): bool
    {
        if (!self::inside($px, $py, self::R)) {
            return false;
        }
        for ($i = 0; $i < 16; $i++) {
            if ($this->gone[$i] || $i === $ignore) {
                continue;
            }
            $dx = $this->x[$i] - $px;
            $dy = $this->y[$i] - $py;
            if (sqrt($dx * $dx + $dy * $dy) < 2 * self::R + 0.5) {
                return false;
            }
        }
        return true;
    }

    /** Puts a ball back: the foot spot, or the nearest free point on the long string. */
    public function respot(int $n): void
    {
        $spot = null;
        for ($px = 750.0; $px <= self::WIDTH - self::R && $spot === null; $px += 2) {
            if ($this->isFree($px, 250.0, $n)) {
                $spot = $px;
            }
        }
        for ($px = 750.0; $px >= self::R && $spot === null; $px -= 2) {
            if ($this->isFree($px, 250.0, $n)) {
                $spot = $px;
            }
        }
        $this->x[$n] = $spot ?? 750.0;
        $this->y[$n] = 250.0;
        $this->vx[$n] = 0.0;
        $this->vy[$n] = 0.0;
        $this->gone[$n] = false;
    }

    /** Returns the cue ball to the table after a scratch. */
    public function respotCue(): void
    {
        $spot = null;
        for ($px = 250.0; $px >= self::R && $spot === null; $px -= 2) {
            if ($this->isFree($px, 250.0, 0)) {
                $spot = $px;
            }
        }
        $this->x[0] = $spot ?? 250.0;
        $this->y[0] = 250.0;
        $this->vx[0] = 0.0;
        $this->vy[0] = 0.0;
        $this->gone[0] = false;
    }

    /** Ball in hand: moves the cue ball, or returns false if the spot is taken. */
    public function placeCue(float $px, float $py, bool $behindHeadString): bool
    {
        $maxX = $behindHeadString ? self::HEAD_STRING_X : self::WIDTH - self::R;
        $cx = max(self::R, min($maxX, $px));
        $cy = max(self::R, min(self::HEIGHT - self::R, $py));
        if (!$this->isFree($cx, $cy, 0)) {
            return false;
        }
        $this->x[0] = $cx;
        $this->y[0] = $cy;
        return true;
    }

    /** @return array{0:float,1:float} */
    public function cuePosition(): array
    {
        return [$this->x[0], $this->y[0]];
    }

    /** ($dirX, $dirY) is the unit aim direction exactly as the app computed it. */
    public function shoot(float $dirX, float $dirY, float $power, float $spinX, float $spinY): void
    {
        $speed = self::MIN_SPEED + (self::MAX_SPEED - self::MIN_SPEED) * max(0.0, min(1.0, $power));
        $this->vx[0] = $dirX * $speed;
        $this->vy[0] = $dirY * $speed;
        $this->spinX = max(-1.0, min(1.0, $spinX));
        $this->spinY = max(-1.0, min(1.0, $spinY));
    }

    private function moving(): bool
    {
        for ($i = 0; $i < 16; $i++) {
            if (!$this->gone[$i] && ($this->vx[$i] != 0 || $this->vy[$i] != 0)) {
                return true;
            }
        }
        return false;
    }

    /** Runs the shot until every ball rests. Returns its duration in seconds. */
    public function simulate(): float
    {
        $steps = 0;
        while ($steps < self::MAX_STEPS && $this->moving()) {
            $this->step();
            $steps++;
        }
        for ($i = 0; $i < 16; $i++) {
            $this->vx[$i] = 0.0;
            $this->vy[$i] = 0.0;
        }
        return $steps * self::DT;
    }

    /** @return array{firstContact:?int,pocketed:list<int>,cuePocketed:bool,railContact:bool,railAfterContact:bool,objectBallsToRail:int,pocketOf:array<int,int>} */
    public function outcome(): array
    {
        return [
            'firstContact' => $this->firstContact,
            'pocketed' => $this->pocketed,
            'cuePocketed' => $this->cuePocketed,
            'railContact' => $this->railContact,
            'railAfterContact' => $this->railAfterContact,
            'objectBallsToRail' => count($this->railBalls),
            'pocketOf' => $this->pocketOf,
        ];
    }

    private function step(): void
    {
        $dt = self::DT;
        for ($i = 0; $i < 16; $i++) {
            if ($this->gone[$i] || ($this->vx[$i] == 0 && $this->vy[$i] == 0)) {
                continue;
            }
            $speed = sqrt($this->vx[$i] * $this->vx[$i] + $this->vy[$i] * $this->vy[$i]);
            $drop = (self::SLIDE_DECEL + self::DRAG * $speed) * $dt;
            if ($speed <= $drop || $speed < self::REST_SPEED) {
                $this->vx[$i] = 0.0;
                $this->vy[$i] = 0.0;
                continue;
            }
            $k = ($speed - $drop) / $speed;
            $this->vx[$i] = $this->vx[$i] * $k;
            $this->vy[$i] = $this->vy[$i] * $k;
            $this->x[$i] = $this->x[$i] + $this->vx[$i] * $dt;
            $this->y[$i] = $this->y[$i] + $this->vy[$i] * $dt;
        }
        $this->collideBalls();
        $this->collideCushions();
        $this->checkPockets();
    }

    private function collideBalls(): void
    {
        $r = self::R;
        for ($i = 0; $i < 16; $i++) {
            if ($this->gone[$i]) {
                continue;
            }
            for ($j = $i + 1; $j < 16; $j++) {
                if ($this->gone[$j]) {
                    continue;
                }
                $iMoving = $this->vx[$i] != 0 || $this->vy[$i] != 0;
                $jMoving = $this->vx[$j] != 0 || $this->vy[$j] != 0;
                if (!$iMoving && !$jMoving) {
                    continue;
                }
                $dx = $this->x[$j] - $this->x[$i];
                $dy = $this->y[$j] - $this->y[$i];
                $dist2 = $dx * $dx + $dy * $dy;
                if ($dist2 >= 4 * $r * $r || $dist2 == 0) {
                    continue;
                }
                $dist = sqrt($dist2);
                $inv = 1 / $dist;
                $nx = $dx * $inv;
                $ny = $dy * $inv;
                $half = (2 * $r - $dist) / 2;
                $this->x[$i] = $this->x[$i] - $nx * $half;
                $this->y[$i] = $this->y[$i] - $ny * $half;
                $this->x[$j] = $this->x[$j] + $nx * $half;
                $this->y[$j] = $this->y[$j] + $ny * $half;
                $rel = ($this->vx[$i] - $this->vx[$j]) * $nx + ($this->vy[$i] - $this->vy[$j]) * $ny;
                if ($rel <= 0) {
                    continue;
                }
                $cueSpeed = sqrt($this->vx[$i] * $this->vx[$i] + $this->vy[$i] * $this->vy[$i]);
                $cueDirX = $cueSpeed == 0 ? 0.0 : $this->vx[$i] / $cueSpeed;
                $cueDirY = $cueSpeed == 0 ? 0.0 : $this->vy[$i] / $cueSpeed;
                $impulse = (1 + self::BALL_RESTITUTION) / 2 * $rel;
                $this->vx[$i] = $this->vx[$i] - $nx * $impulse;
                $this->vy[$i] = $this->vy[$i] - $ny * $impulse;
                $this->vx[$j] = $this->vx[$j] + $nx * $impulse;
                $this->vy[$j] = $this->vy[$j] + $ny * $impulse;
                if ($i === 0 && $this->firstContact === null) {
                    $this->firstContact = $j;
                    // Follow / draw: top spin drives the cue ball on, back spin pulls it back.
                    if ($cueSpeed > 0) {
                        $f = $this->spinY * 0.5 * $rel;
                        $this->vx[0] = $this->vx[0] + $cueDirX * $f;
                        $this->vy[0] = $this->vy[0] + $cueDirY * $f;
                    }
                    $this->spinY = 0.0;
                }
            }
        }
    }

    private function collideCushions(): void
    {
        $r = self::R;
        for ($i = 0; $i < 16; $i++) {
            if ($this->gone[$i] || ($this->vx[$i] == 0 && $this->vy[$i] == 0)) {
                continue;
            }
            foreach (self::CUSHIONS as [$ax, $ay, $bx, $by, $cnx, $cny]) {
                $abx = $bx - $ax;
                $aby = $by - $ay;
                $t = (($this->x[$i] - $ax) * $abx + ($this->y[$i] - $ay) * $aby) / ($abx * $abx + $aby * $aby);
                $t = max(0.0, min(1.0, $t));
                $qx = $ax + $abx * $t;
                $qy = $ay + $aby * $t;
                $dx = $this->x[$i] - $qx;
                $dy = $this->y[$i] - $qy;
                $dist = sqrt($dx * $dx + $dy * $dy);
                if ($dist >= $r) {
                    continue;
                }
                // On the straight part use the cushion normal; at the jaw tips
                // bounce off the tip itself.
                if (($t > 0 && $t < 1) || $dist == 0) {
                    $nx = $cnx;
                    $ny = $cny;
                } else {
                    $inv = 1 / $dist;
                    $nx = $dx * $inv;
                    $ny = $dy * $inv;
                }
                $vn = $this->vx[$i] * $nx + $this->vy[$i] * $ny;
                $this->x[$i] = $qx + $nx * $r;
                $this->y[$i] = $qy + $ny * $r;
                if ($vn >= 0) {
                    continue;
                }
                $f = (1 + self::CUSHION_RESTITUTION) * $vn;
                $this->vx[$i] = $this->vx[$i] - $nx * $f;
                $this->vy[$i] = $this->vy[$i] - $ny * $f;
                if ($i === 0 && $this->spinX != 0) {
                    $g = $this->spinX * 0.3 * abs($vn);
                    $this->vx[0] = $this->vx[0] + (-$ny) * $g;
                    $this->vy[0] = $this->vy[0] + $nx * $g;
                    $this->spinX *= 0.4;
                }
                $this->railContact = true;
                if ($this->firstContact !== null) {
                    $this->railAfterContact = true;
                }
                if ($i !== 0) {
                    $this->railBalls[$i] = true;
                }
            }
        }
    }

    private function checkPockets(): void
    {
        for ($i = 0; $i < 16; $i++) {
            if ($this->gone[$i]) {
                continue;
            }
            $hit = -1;
            foreach (self::POCKETS as $p => [$cx, $cy, $radius]) {
                $dx = $this->x[$i] - $cx;
                $dy = $this->y[$i] - $cy;
                if (sqrt($dx * $dx + $dy * $dy) < $radius) {
                    $hit = $p;
                }
            }
            if ($hit < 0 && !self::inside($this->x[$i], $this->y[$i], -4.0)) {
                // Slipped through a mouth past the capture circle: nearest pocket takes it.
                $best = INF;
                foreach (self::POCKETS as $p => [$cx, $cy]) {
                    $dx = $this->x[$i] - $cx;
                    $dy = $this->y[$i] - $cy;
                    $d = sqrt($dx * $dx + $dy * $dy);
                    if ($d < $best) {
                        $best = $d;
                        $hit = $p;
                    }
                }
            }
            if ($hit < 0) {
                continue;
            }
            $this->gone[$i] = true;
            $this->vx[$i] = 0.0;
            $this->vy[$i] = 0.0;
            if ($i === 0) {
                $this->cuePocketed = true;
            } else {
                $this->pocketed[] = $i;
                $this->pocketOf[$i] = $hit;
            }
        }
    }
}
