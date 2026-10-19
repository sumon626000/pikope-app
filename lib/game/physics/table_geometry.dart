import 'vec2.dart';

class Pocket {
  const Pocket(this.center, this.radius, this.aim);

  /// Capture circle: a ball whose centre enters it drops.
  final Vec2 center;
  final double radius;

  /// Point on the mouth a shot should be aimed at.
  final Vec2 aim;
}

class Cushion {
  const Cushion(this.a, this.b, this.normal);

  final Vec2 a;
  final Vec2 b;

  /// Unit normal pointing into the playfield.
  final Vec2 normal;
}

/// Logical table: a 2:1 playfield with the origin at the top-left cushion
/// corner. The head string is on the left, the rack on the right.
class TableGeometry {
  static const double width = 1000;
  static const double height = 500;
  static const double ballRadius = 16;
  static const double headStringX = 250;
  static const Vec2 headSpot = Vec2(250, 250);
  static const Vec2 footSpot = Vec2(750, 250);

  static const double _cornerMouth = 38;
  static const double _sideMouth = 30;

  static const List<Pocket> pockets = [
    Pocket(Vec2(-6, -6), 30, Vec2(10, 10)),
    Pocket(Vec2(500, -20), 24, Vec2(500, 0)),
    Pocket(Vec2(1006, -6), 30, Vec2(990, 10)),
    Pocket(Vec2(-6, 506), 30, Vec2(10, 490)),
    Pocket(Vec2(500, 520), 24, Vec2(500, 500)),
    Pocket(Vec2(1006, 506), 30, Vec2(990, 490)),
  ];

  static const List<Cushion> cushions = [
    Cushion(Vec2(_cornerMouth, 0), Vec2(500 - _sideMouth, 0), Vec2(0, 1)),
    Cushion(Vec2(500 + _sideMouth, 0), Vec2(width - _cornerMouth, 0), Vec2(0, 1)),
    Cushion(Vec2(_cornerMouth, height), Vec2(500 - _sideMouth, height), Vec2(0, -1)),
    Cushion(Vec2(500 + _sideMouth, height), Vec2(width - _cornerMouth, height), Vec2(0, -1)),
    Cushion(Vec2(0, _cornerMouth), Vec2(0, height - _cornerMouth), Vec2(1, 0)),
    Cushion(Vec2(width, _cornerMouth), Vec2(width, height - _cornerMouth), Vec2(-1, 0)),
  ];

  static bool insidePlayfield(Vec2 p, {double margin = ballRadius}) =>
      p.x >= margin && p.x <= width - margin && p.y >= margin && p.y <= height - margin;
}
