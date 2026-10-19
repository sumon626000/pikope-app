<?php
declare(strict_types=1);

namespace App\Game;

/**
 * The carrom board simulation, server side. A line-for-line port of the
 * app's lib/game/carrom/carrom_physics.dart: same constants, same order of
 * floating-point operations, so a stroke played here comes to rest exactly
 * where the app's own animation of it does. The server's result is the
 * authority; the apps only draw it.
 *
 * Disc indices: 0 striker, 1..9 white, 10..18 black, 19 the red queen.
 */
final class CarromPhysics
{
    public const COUNT = 20;
    public const STRIKER = 0;
    public const QUEEN = 19;
    public const SIZE = 1000.0;
    public const PIECE_R = 27.0;
    public const STRIKER_R = 37.0;
    private const PIECE_MASS = 1.0;
    private const STRIKER_MASS = 2.4;
    private const DT = 1 / 300;
    private const MAX_SPEED = 2400.0;
    private const MIN_SPEED = 250.0;
    private const SLIDE_DECEL = 150.0;
    private const DRAG = 0.5;
    private const REST_SPEED = 2;
    private const DISC_RESTITUTION = 0.92;
    private const CUSHION_RESTITUTION = 0.72;
    private const MAX_STEPS = 20000;

    public const BASE_FAR = 160.0;
    public const BASE_NEAR = 840.0;
    public const BASE_MIN_X = 220.0;
    public const BASE_MAX_X = 780.0;

    /** Corner pockets: centre x, centre y, capture radius. */
    public const POCKETS = [
        [36.0, 36.0, 50.0], [964.0, 36.0, 50.0], [36.0, 964.0, 50.0], [964.0, 964.0, 50.0],
    ];

    /** Cushion segments: ax, ay, bx, by, normal x, normal y. */
    private const CUSHIONS = [
        [80.0, 0.0, 920.0, 0.0, 0.0, 1.0], [80.0, 1000.0, 920.0, 1000.0, 0.0, -1.0],
        [0.0, 80.0, 0.0, 920.0, 1.0, 0.0], [1000.0, 80.0, 1000.0, 920.0, -1.0, 0.0],
    ];

    /** @var list<float> */
    public array $x = [];
    /** @var list<float> */
    public array $y = [];
    /** @var list<float> */
    private array $vx = [];
    /** @var list<float> */
    private array $vy = [];
    /** @var list<bool> */
    public array $gone = [];

    /** @var list<int> */
    public array $pocketed = [];
    public bool $strikerPocketed = false;
    public ?int $firstContact = null;

    public static function radiusOf(int $i): float
    {
        return $i === self::STRIKER ? self::STRIKER_R : self::PIECE_R;
    }

    private static function massOf(int $i): float
    {
        return $i === self::STRIKER ? self::STRIKER_MASS : self::PIECE_MASS;
    }

    /** Which seat's pieces these are: 0 white (1..9), 1 black (10..18), null striker/queen. */
    public static function colourOf(int $i): ?int
    {
        return $i >= 1 && $i <= 9 ? 0 : ($i >= 10 && $i <= 18 ? 1 : null);
    }

    /** @param list<array{0:float|int,1:float|int,2:bool}> $discs */
    public static function fromState(array $discs): self
    {
        $w = new self();
        for ($i = 0; $i < self::COUNT; $i++) {
            $w->x[$i] = (float) $discs[$i][0];
            $w->y[$i] = (float) $discs[$i][1];
            $w->vx[$i] = 0.0;
            $w->vy[$i] = 0.0;
            $w->gone[$i] = (bool) $discs[$i][2];
        }
        return $w;
    }

    /** @return list<array{0:float,1:float,2:bool}> */
    public function toState(): array
    {
        $out = [];
        for ($i = 0; $i < self::COUNT; $i++) {
            $out[] = [$this->x[$i], $this->y[$i], $this->gone[$i]];
        }
        return $out;
    }

    /**
     * The opening layout: the queen on the centre, six pieces around it and
     * twelve around those, colours alternating. The striker is off the board.
     * @return list<array{0:float,1:float,2:bool}>
     */
    public static function opening(): array
    {
        $discs = array_fill(0, self::COUNT, [0.0, 0.0, true]);
        $c = 500.0;
        $d = 2 * self::PIECE_R + 1.0;
        $discs[self::QUEEN] = [$c, $c, false];
        $white = 1;
        $black = 10;
        for ($k = 0; $k < 6; $k++) {
            $a = -M_PI / 2 + $k * M_PI / 3;
            $idx = $k % 2 === 0 ? $black++ : $white++;
            $discs[$idx] = [$c + $d * cos($a), $c + $d * sin($a), false];
        }
        for ($k = 0; $k < 12; $k++) {
            $corner = intdiv($k, 2);
            $a0 = -M_PI / 2 + $corner * M_PI / 3;
            $a1 = $a0 + M_PI / 3;
            if ($k % 2 === 0) {
                $px = $c + 2 * $d * cos($a0);
                $py = $c + 2 * $d * sin($a0);
            } else {
                $px = $c + $d * (cos($a0) + cos($a1));
                $py = $c + $d * (sin($a0) + sin($a1));
            }
            $idx = $k % 2 === 0 ? $white++ : $black++;
            $discs[$idx] = [$px, $py, false];
        }
        return $discs;
    }

    private function free(float $px, float $py, int $ignore, float $r): bool
    {
        if ($px < $r || $px > self::SIZE - $r || $py < $r || $py > self::SIZE - $r) {
            return false;
        }
        for ($i = 0; $i < self::COUNT; $i++) {
            if ($this->gone[$i] || $i === $ignore) {
                continue;
            }
            $dx = $this->x[$i] - $px;
            $dy = $this->y[$i] - $py;
            if (sqrt($dx * $dx + $dy * $dy) < $r + self::radiusOf($i) + 0.5) {
                return false;
            }
        }
        return true;
    }

    /** Puts a piece back on the centre, or the nearest free spot around it. */
    public function returnToCentre(int $i): void
    {
        $this->gone[$i] = true;
        $placed = false;
        for ($ring = 0; $ring < 30 && !$placed; $ring++) {
            $rad = $ring * 12.0;
            $steps = $ring === 0 ? 1 : 12 * $ring;
            for ($k = 0; $k < $steps && !$placed; $k++) {
                $a = 2 * M_PI * $k / $steps;
                $px = 500 + $rad * cos($a);
                $py = 500 + $rad * sin($a);
                if ($this->free($px, $py, $i, self::PIECE_R)) {
                    $this->x[$i] = $px;
                    $this->y[$i] = $py;
                    $placed = true;
                }
            }
        }
        if (!$placed) {
            $this->x[$i] = 500.0;
            $this->y[$i] = 500.0;
        }
        $this->vx[$i] = 0.0;
        $this->vy[$i] = 0.0;
        $this->gone[$i] = false;
    }

    /** Places the striker on $seat's base line at $px, nudged clear of pieces. Returns its x. */
    public function placeStriker(int $seat, float $px): float
    {
        $py = $seat === 0 ? self::BASE_NEAR : self::BASE_FAR;
        $cx = max(self::BASE_MIN_X, min(self::BASE_MAX_X, $px));
        $this->gone[self::STRIKER] = true;
        $found = null;
        for ($off = 0.0; $off <= self::BASE_MAX_X - self::BASE_MIN_X && $found === null; $off += 2) {
            foreach ([$cx + $off, $cx - $off] as $sx) {
                if ($sx < self::BASE_MIN_X || $sx > self::BASE_MAX_X) {
                    continue;
                }
                if ($this->free($sx, $py, self::STRIKER, self::STRIKER_R)) {
                    $found = $sx;
                    break;
                }
            }
        }
        $this->x[self::STRIKER] = $found ?? $cx;
        $this->y[self::STRIKER] = $py;
        $this->vx[self::STRIKER] = 0.0;
        $this->vy[self::STRIKER] = 0.0;
        $this->gone[self::STRIKER] = false;
        return $this->x[self::STRIKER];
    }

    public function shoot(float $dirX, float $dirY, float $power): void
    {
        $this->pocketed = [];
        $this->strikerPocketed = false;
        $this->firstContact = null;
        $speed = self::MIN_SPEED + (self::MAX_SPEED - self::MIN_SPEED) * max(0.0, min(1.0, $power));
        $this->vx[self::STRIKER] = $dirX * $speed;
        $this->vy[self::STRIKER] = $dirY * $speed;
    }

    private function moving(): bool
    {
        for ($i = 0; $i < self::COUNT; $i++) {
            if (!$this->gone[$i] && ($this->vx[$i] != 0 || $this->vy[$i] != 0)) {
                return true;
            }
        }
        return false;
    }

    /** Runs the stroke until everything rests. Returns its duration in seconds. */
    public function simulate(): float
    {
        $steps = 0;
        while ($steps < self::MAX_STEPS && $this->moving()) {
            $this->step();
            $steps++;
        }
        for ($i = 0; $i < self::COUNT; $i++) {
            $this->vx[$i] = 0.0;
            $this->vy[$i] = 0.0;
        }
        return $steps * self::DT;
    }

    private function step(): void
    {
        $dt = self::DT;
        for ($i = 0; $i < self::COUNT; $i++) {
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
        $this->collideDiscs();
        $this->collideCushions();
        $this->checkPockets();
    }

    private function collideDiscs(): void
    {
        for ($i = 0; $i < self::COUNT; $i++) {
            if ($this->gone[$i]) {
                continue;
            }
            for ($j = $i + 1; $j < self::COUNT; $j++) {
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
                $rr = self::radiusOf($i) + self::radiusOf($j);
                if ($dist2 >= $rr * $rr || $dist2 == 0) {
                    continue;
                }
                $dist = sqrt($dist2);
                $inv = 1 / $dist;
                $nx = $dx * $inv;
                $ny = $dy * $inv;
                $half = ($rr - $dist) / 2;
                $this->x[$i] = $this->x[$i] - $nx * $half;
                $this->y[$i] = $this->y[$i] - $ny * $half;
                $this->x[$j] = $this->x[$j] + $nx * $half;
                $this->y[$j] = $this->y[$j] + $ny * $half;
                $rel = ($this->vx[$i] - $this->vx[$j]) * $nx + ($this->vy[$i] - $this->vy[$j]) * $ny;
                if ($rel <= 0) {
                    continue;
                }
                $mi = self::massOf($i);
                $mj = self::massOf($j);
                $impulse = (1 + self::DISC_RESTITUTION) * $rel / (1 / $mi + 1 / $mj);
                $this->vx[$i] = $this->vx[$i] - $nx * ($impulse / $mi);
                $this->vy[$i] = $this->vy[$i] - $ny * ($impulse / $mi);
                $this->vx[$j] = $this->vx[$j] + $nx * ($impulse / $mj);
                $this->vy[$j] = $this->vy[$j] + $ny * ($impulse / $mj);
                if ($i === self::STRIKER && $this->firstContact === null) {
                    $this->firstContact = $j;
                }
            }
        }
    }

    private function collideCushions(): void
    {
        for ($i = 0; $i < self::COUNT; $i++) {
            if ($this->gone[$i] || ($this->vx[$i] == 0 && $this->vy[$i] == 0)) {
                continue;
            }
            $r = self::radiusOf($i);
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
            }
        }
    }

    private function checkPockets(): void
    {
        for ($i = 0; $i < self::COUNT; $i++) {
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
            if ($hit < 0 && ($this->x[$i] < -4 || $this->x[$i] > self::SIZE + 4 || $this->y[$i] < -4 || $this->y[$i] > self::SIZE + 4)) {
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
            if ($i === self::STRIKER) {
                $this->strikerPocketed = true;
            } else {
                $this->pocketed[] = $i;
            }
        }
    }
}
