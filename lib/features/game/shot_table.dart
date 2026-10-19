import 'package:flutter/foundation.dart';

import '../../game/physics/physics_world.dart';
import '../../game/physics/vec2.dart';

enum BannerTone { info, good, bad, gold }

class GameBanner {
  const GameBanner(this.lines, this.tone, {this.seconds = 2.0});

  final List<String> lines;
  final BannerTone tone;
  final double seconds;
}

/// A ball on its way down a pocket (render-only).
class SinkingBall {
  SinkingBall(this.number, this.from, this.pocket, this.start);

  final int number;
  final Vec2 from;
  final int pocket;
  final double start;

  static const seconds = 0.28;
}

/// What the table, power bar and spin control need from whichever game is
/// running, so the same widgets serve every game mode.
abstract class ShotTable {
  PhysicsWorld get world;

  /// Ticks every animation frame (drives the table painter).
  ValueNotifier<int> get frame;
  double get time;

  double get aimAngle;
  double get power;
  Vec2 get spin;

  /// The table is drawn turned 180 degrees for this viewer.
  bool get viewRotated;
  bool get showAimGuide;

  /// Online: another player is lining up a shot; their cue is drawn too.
  bool get showRemoteCue;

  /// Cue (look) of the player at the table.
  String get cueId;
  bool get showBallInHand;
  bool get canPlaceCue;
  bool get canShoot;

  /// Balls ringed as "yours to play".
  Set<int> get highlightBalls;

  /// Ball ringed in gold as the declared target.
  int? get targetBall;

  /// Pocket marked as called (8-ball), if any.
  int? get calledPocket;

  /// Whether hitting [ball] first would be a foul (turns the guide red).
  bool isWrongContact(int ball);

  List<SinkingBall> get sinking;

  void aimAt(Vec2 worldPoint);
  void nudgeAim(double radians);
  void moveCue(Vec2 worldPoint);

  /// A ball was tapped; returns whether it became the target.
  bool selectBall(int ball);

  /// A pocket was tapped; returns whether it was accepted as the call.
  bool tapPocket(int index);

  void setPower(double value);
  void releaseShot();
  void setSpin(Vec2 value);
}
