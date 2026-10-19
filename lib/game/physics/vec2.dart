import 'dart:math';

class Vec2 {
  const Vec2(this.x, this.y);

  final double x;
  final double y;

  static const zero = Vec2(0, 0);

  factory Vec2.fromAngle(double a) => Vec2(cos(a), sin(a));

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);

  double dot(Vec2 o) => x * o.x + y * o.y;
  double get length => sqrt(x * x + y * y);
  double get length2 => x * x + y * y;
  double get angle => atan2(y, x);
  double distanceTo(Vec2 o) => (this - o).length;

  Vec2 get normalized {
    final l = length;
    return l == 0 ? zero : Vec2(x / l, y / l);
  }

  /// Counter-clockwise perpendicular.
  Vec2 get perp => Vec2(-y, x);

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}
