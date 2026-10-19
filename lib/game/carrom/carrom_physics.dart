import 'dart:math';

import '../physics/vec2.dart';

/// Fixed-step carrom board simulation: the striker and 19 pieces sliding on a
/// 1000 x 1000 playfield with a pocket in each corner.
///
/// backend/src/Game/CarromPhysics.php is a line-for-line port: same
/// constants, same order of floating-point operations, so a stroke played
/// there comes to rest exactly where this animation of it does. If you change
/// one side, change the other.
///
/// Disc indices: 0 striker, 1..9 white, 10..18 black, 19 the red queen.
class CarromWorld {
  CarromWorld() {
    for (var i = 0; i < count; i++) {
      x.add(0);
      y.add(0);
      vx.add(0);
      vy.add(0);
      gone.add(true);
    }
  }

  static const int count = 20;
  static const int striker = 0;
  static const int queen = 19;
  static const double size = 1000;
  static const double pieceR = 27;
  static const double strikerR = 37;
  static const double pieceMass = 1;
  static const double strikerMass = 2.4;
  static const double fixedDt = 1 / 300;
  static const double maxSpeed = 2400;
  static const double minSpeed = 250;
  static const double _slideDecel = 150;
  static const double _dragCoeff = 0.5;
  static const double _restSpeed = 2;
  static const double _discRestitution = 0.92;
  static const double _cushionRestitution = 0.72;
  static const int _maxSteps = 20000;

  /// Where a seated player's striker rests: the base line nearest to them.
  static const double baseFar = 160; // seat 1 (top)
  static const double baseNear = 840; // seat 0 (bottom)

  /// Striker may slide between the two base-line circles.
  static const double baseMinX = 220;
  static const double baseMaxX = 780;

  /// Corner pockets: centre and capture radius.
  static const List<List<double>> pockets = [
    [36, 36, 50], [964, 36, 50], [36, 964, 50], [964, 964, 50],
  ];

  /// Cushions: ax, ay, bx, by, inward normal x, y (gaps are the pocket mouths).
  static const List<List<double>> cushions = [
    [80, 0, 920, 0, 0, 1], [80, 1000, 920, 1000, 0, -1],
    [0, 80, 0, 920, 1, 0], [1000, 80, 1000, 920, -1, 0],
  ];

  final List<double> x = [];
  final List<double> y = [];
  final List<double> vx = [];
  final List<double> vy = [];
  final List<bool> gone = [];

  final List<int> pocketed = [];
  bool strikerPocketed = false;
  int? firstContact;

  /// Sound / effect hints produced while stepping.
  final List<CarromEvent> events = [];

  static double radiusOf(int i) => i == striker ? strikerR : pieceR;
  static double massOf(int i) => i == striker ? strikerMass : pieceMass;

  /// Which seat's pieces these are: 0 white (1..9), 1 black (10..18).
  static int? colourOf(int i) => i >= 1 && i <= 9 ? 0 : (i >= 10 && i <= 18 ? 1 : null);

  CarromWorld clone() {
    final w = CarromWorld();
    for (var i = 0; i < count; i++) {
      w.x[i] = x[i];
      w.y[i] = y[i];
      w.vx[i] = vx[i];
      w.vy[i] = vy[i];
      w.gone[i] = gone[i];
    }
    return w;
  }

  /// Loads disc positions as the server sends them: [x, y, gone] per disc.
  void setDiscs(List<List<dynamic>> discs) {
    for (var i = 0; i < count && i < discs.length; i++) {
      x[i] = (discs[i][0] as num).toDouble();
      y[i] = (discs[i][1] as num).toDouble();
      vx[i] = 0;
      vy[i] = 0;
      gone[i] = discs[i][2] as bool;
    }
  }

  List<List<dynamic>> toDiscs() => [for (var i = 0; i < count; i++) [x[i], y[i], gone[i]]];

  // ---------------------------------------------------------------- setup

  /// The opening layout: the queen on the centre, six pieces around it and
  /// twelve around those, colours alternating. The striker is off the board.
  static List<List<dynamic>> opening() {
    final discs = [for (var i = 0; i < count; i++) <dynamic>[0.0, 0.0, true]];
    const c = 500.0;
    const d = 2 * pieceR + 1.0; // a hair of air between neighbours
    discs[queen] = [c, c, false];
    var white = 1, black = 10;
    // Inner ring: six at distance d, starting straight up, black first.
    for (var k = 0; k < 6; k++) {
      final a = -pi / 2 + k * pi / 3;
      final idx = k.isEven ? black++ : white++;
      discs[idx] = [c + d * cos(a), c + d * sin(a), false];
    }
    // Outer ring: twelve at the hexagon of side 2d (corners and edge midpoints).
    for (var k = 0; k < 12; k++) {
      final corner = k ~/ 2;
      final a0 = -pi / 2 + corner * pi / 3;
      final a1 = a0 + pi / 3;
      final double px, py;
      if (k.isEven) {
        px = c + 2 * d * cos(a0);
        py = c + 2 * d * sin(a0);
      } else {
        px = c + d * (cos(a0) + cos(a1));
        py = c + d * (sin(a0) + sin(a1));
      }
      final idx = k.isEven ? white++ : black++;
      discs[idx] = [px, py, false];
    }
    return discs;
  }

  bool _free(double px, double py, int ignore, double r) {
    if (px < r || px > size - r || py < r || py > size - r) return false;
    for (var i = 0; i < count; i++) {
      if (gone[i] || i == ignore) continue;
      final dx = x[i] - px, dy = y[i] - py;
      if (sqrt(dx * dx + dy * dy) < r + radiusOf(i) + 0.5) return false;
    }
    return true;
  }

  /// Puts a piece back on the centre, or the nearest free spot around it.
  void returnToCentre(int i) {
    gone[i] = true; // never collides with itself while searching
    var placed = false;
    for (var ring = 0; ring < 30 && !placed; ring++) {
      final rad = ring * 12.0;
      final steps = ring == 0 ? 1 : 12 * ring;
      for (var k = 0; k < steps && !placed; k++) {
        final a = 2 * pi * k / steps;
        final px = 500 + rad * cos(a), py = 500 + rad * sin(a);
        if (_free(px, py, i, pieceR)) {
          x[i] = px;
          y[i] = py;
          placed = true;
        }
      }
    }
    if (!placed) {
      x[i] = 500;
      y[i] = 500;
    }
    vx[i] = 0;
    vy[i] = 0;
    gone[i] = false;
  }

  /// Places the striker on [seat]'s base line at [px], nudged to the nearest
  /// spot that does not overlap a piece. Returns the x it ended up on.
  double placeStriker(int seat, double px) {
    final py = seat == 0 ? baseNear : baseFar;
    final cx = px.clamp(baseMinX, baseMaxX).toDouble();
    gone[striker] = true;
    double? found;
    for (var off = 0.0; off <= baseMaxX - baseMinX && found == null; off += 2) {
      for (final sx in [cx + off, cx - off]) {
        if (sx < baseMinX || sx > baseMaxX) continue;
        if (_free(sx, py, striker, strikerR)) {
          found = sx;
          break;
        }
      }
    }
    x[striker] = found ?? cx;
    y[striker] = py;
    vx[striker] = 0;
    vy[striker] = 0;
    gone[striker] = false;
    return x[striker];
  }

  /// True when the striker can sit at [px] on the base line without touching a piece.
  bool strikerFits(int seat, double px) => _free(px, seat == 0 ? baseNear : baseFar, striker, strikerR);

  // ----------------------------------------------------------------- shot

  void shoot(Vec2 dir, double power) {
    pocketed.clear();
    strikerPocketed = false;
    firstContact = null;
    events.clear();
    final speed = minSpeed + (maxSpeed - minSpeed) * power.clamp(0.0, 1.0);
    vx[striker] = dir.x * speed;
    vy[striker] = dir.y * speed;
  }

  bool get isMoving {
    for (var i = 0; i < count; i++) {
      if (!gone[i] && (vx[i] != 0 || vy[i] != 0)) return true;
    }
    return false;
  }

  /// Runs the stroke until everything rests. Returns its duration in seconds.
  double simulate() {
    var steps = 0;
    while (steps < _maxSteps && isMoving) {
      step();
      steps++;
    }
    for (var i = 0; i < count; i++) {
      vx[i] = 0;
      vy[i] = 0;
    }
    return steps * fixedDt;
  }

  void step() {
    const dt = fixedDt;
    for (var i = 0; i < count; i++) {
      if (gone[i] || (vx[i] == 0 && vy[i] == 0)) continue;
      final speed = sqrt(vx[i] * vx[i] + vy[i] * vy[i]);
      final drop = (_slideDecel + _dragCoeff * speed) * dt;
      if (speed <= drop || speed < _restSpeed) {
        vx[i] = 0;
        vy[i] = 0;
        continue;
      }
      final k = (speed - drop) / speed;
      vx[i] = vx[i] * k;
      vy[i] = vy[i] * k;
      x[i] = x[i] + vx[i] * dt;
      y[i] = y[i] + vy[i] * dt;
    }
    _collideDiscs();
    _collideCushions();
    _checkPockets();
  }

  void _collideDiscs() {
    for (var i = 0; i < count; i++) {
      if (gone[i]) continue;
      for (var j = i + 1; j < count; j++) {
        if (gone[j]) continue;
        final iMoving = vx[i] != 0 || vy[i] != 0;
        final jMoving = vx[j] != 0 || vy[j] != 0;
        if (!iMoving && !jMoving) continue;
        final dx = x[j] - x[i], dy = y[j] - y[i];
        final dist2 = dx * dx + dy * dy;
        final rr = radiusOf(i) + radiusOf(j);
        if (dist2 >= rr * rr || dist2 == 0) continue;
        final dist = sqrt(dist2);
        final inv = 1 / dist;
        final nx = dx * inv, ny = dy * inv;
        final half = (rr - dist) / 2;
        x[i] = x[i] - nx * half;
        y[i] = y[i] - ny * half;
        x[j] = x[j] + nx * half;
        y[j] = y[j] + ny * half;
        final rel = (vx[i] - vx[j]) * nx + (vy[i] - vy[j]) * ny;
        if (rel <= 0) continue;
        final mi = massOf(i), mj = massOf(j);
        final impulse = (1 + _discRestitution) * rel / (1 / mi + 1 / mj);
        vx[i] = vx[i] - nx * (impulse / mi);
        vy[i] = vy[i] - ny * (impulse / mi);
        vx[j] = vx[j] + nx * (impulse / mj);
        vy[j] = vy[j] + ny * (impulse / mj);
        if (i == striker && firstContact == null) firstContact = j;
        events.add(CarromEvent(CarromEventType.hit, (rel / 1400).clamp(0.05, 1.0)));
      }
    }
  }

  void _collideCushions() {
    for (var i = 0; i < count; i++) {
      if (gone[i] || (vx[i] == 0 && vy[i] == 0)) continue;
      final r = radiusOf(i);
      for (final c in cushions) {
        final ax = c[0], ay = c[1], bx = c[2], by = c[3], cnx = c[4], cny = c[5];
        final abx = bx - ax, aby = by - ay;
        var t = ((x[i] - ax) * abx + (y[i] - ay) * aby) / (abx * abx + aby * aby);
        t = t.clamp(0.0, 1.0);
        final qx = ax + abx * t, qy = ay + aby * t;
        final dx = x[i] - qx, dy = y[i] - qy;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist >= r) continue;
        final double nx, ny;
        if ((t > 0 && t < 1) || dist == 0) {
          nx = cnx;
          ny = cny;
        } else {
          final inv = 1 / dist;
          nx = dx * inv;
          ny = dy * inv;
        }
        final vn = vx[i] * nx + vy[i] * ny;
        x[i] = qx + nx * r;
        y[i] = qy + ny * r;
        if (vn >= 0) continue;
        final f = (1 + _cushionRestitution) * vn;
        vx[i] = vx[i] - nx * f;
        vy[i] = vy[i] - ny * f;
        events.add(CarromEvent(CarromEventType.cushion, (vn.abs() / 1400).clamp(0.05, 1.0)));
      }
    }
  }

  void _checkPockets() {
    for (var i = 0; i < count; i++) {
      if (gone[i]) continue;
      var hit = -1;
      for (var p = 0; p < pockets.length; p++) {
        final dx = x[i] - pockets[p][0], dy = y[i] - pockets[p][1];
        if (sqrt(dx * dx + dy * dy) < pockets[p][2]) hit = p;
      }
      if (hit < 0 && (x[i] < -4 || x[i] > size + 4 || y[i] < -4 || y[i] > size + 4)) {
        // Slipped through a mouth past the capture circle: nearest pocket takes it.
        var best = double.infinity;
        for (var p = 0; p < pockets.length; p++) {
          final dx = x[i] - pockets[p][0], dy = y[i] - pockets[p][1];
          final d = sqrt(dx * dx + dy * dy);
          if (d < best) {
            best = d;
            hit = p;
          }
        }
      }
      if (hit < 0) continue;
      gone[i] = true;
      vx[i] = 0;
      vy[i] = 0;
      if (i == striker) {
        strikerPocketed = true;
      } else {
        pocketed.add(i);
      }
      events.add(CarromEvent(CarromEventType.pocket, 1, disc: i, pocket: hit, at: Vec2(x[i], y[i])));
    }
  }

  // ------------------------------------------------------------------ aim

  /// Straight-line prediction of the striker's first impact (for the guide).
  /// Where the striker, shot from [from] (default: where it sits) along
  /// [dir], first meets a piece or a cushion, and the directions after that.
  CarromAim predict(Vec2 dir, {Vec2? from}) {
    final ox = from?.x ?? x[striker], oy = from?.y ?? y[striker];
    var bestT = double.infinity;
    int? hitDisc;
    for (var i = 1; i < count; i++) {
      if (gone[i]) continue;
      final ocx = x[i] - ox, ocy = y[i] - oy;
      final proj = ocx * dir.x + ocy * dir.y;
      if (proj <= 0) continue;
      final perp2 = ocx * ocx + ocy * ocy - proj * proj;
      final rr = strikerR + pieceR;
      if (perp2 >= rr * rr) continue;
      final t = proj - sqrt(rr * rr - perp2);
      if (t >= 0 && t < bestT) {
        bestT = t;
        hitDisc = i;
      }
    }
    var wallT = double.infinity;
    if (dir.x > 0) wallT = min(wallT, (size - strikerR - ox) / dir.x);
    if (dir.x < 0) wallT = min(wallT, (strikerR - ox) / dir.x);
    if (dir.y > 0) wallT = min(wallT, (size - strikerR - oy) / dir.y);
    if (dir.y < 0) wallT = min(wallT, (strikerR - oy) / dir.y);
    if (hitDisc == null || wallT < bestT) {
      return CarromAim(ghost: Vec2(ox + dir.x * max(0, wallT), oy + dir.y * max(0, wallT)));
    }
    final ghost = Vec2(ox + dir.x * bestT, oy + dir.y * bestT);
    final targetDir = (Vec2(x[hitDisc], y[hitDisc]) - ghost).normalized;
    final tangent = dir - targetDir * dir.dot(targetDir);
    return CarromAim(
      ghost: ghost,
      hitDisc: hitDisc,
      targetDir: targetDir,
      strikerDir: tangent.length < 0.05 ? null : tangent.normalized,
    );
  }
}

enum CarromEventType { hit, cushion, pocket }

class CarromEvent {
  const CarromEvent(this.type, this.intensity, {this.disc = 0, this.pocket = 0, this.at = Vec2.zero});

  final CarromEventType type;
  final double intensity;
  final int disc;
  final int pocket;
  final Vec2 at;
}

class CarromAim {
  const CarromAim({required this.ghost, this.hitDisc, this.targetDir, this.strikerDir});

  final Vec2 ghost;
  final int? hitDisc;
  final Vec2? targetDir;
  final Vec2? strikerDir;
}
