import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/cues.dart';
import '../../../core/app_theme.dart';
import '../../../core/perf.dart';
import '../../../data/demo_data.dart';
import '../../../game/physics/physics_world.dart';
import '../../../game/physics/table_geometry.dart';
import '../../../game/physics/vec2.dart';
import '../shot_table.dart';
import 'ball_painter.dart';
import 'table_art.dart';

/// Maps the logical playfield onto the table artwork. In every supplied
/// 600x351 table image the cushion noses enclose (50, 50.5)-(550, 300.5).
class TableProjection {
  const TableProjection(this.size, this.rotated);

  final Size size;
  final bool rotated;

  static const double imageWidth = 600;
  static const double imageHeight = 351;
  static const double _fieldLeft = 50;
  static const double _fieldTop = 50.5;

  double get _px => size.width / imageWidth;
  double get scale => _px / 2;

  Offset toLocal(Vec2 w) {
    final x = rotated ? TableGeometry.width - w.x : w.x;
    final y = rotated ? TableGeometry.height - w.y : w.y;
    return Offset((_fieldLeft + x / 2) * _px, (_fieldTop + y / 2) * _px);
  }

  Vec2 toWorld(Offset l) {
    final x = (l.dx / _px - _fieldLeft) * 2;
    final y = (l.dy / _px - _fieldTop) * 2;
    return rotated ? Vec2(TableGeometry.width - x, TableGeometry.height - y) : Vec2(x, y);
  }

  Offset dir(Vec2 d) => rotated ? Offset(-d.x, -d.y) : Offset(d.x, d.y);
}

class TableView extends StatefulWidget {
  const TableView({super.key, required this.controller, required this.skin});

  final ShotTable controller;
  final TableSkin skin;

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  ui.Image? _image;
  bool _draggingCue = false;
  Offset? _lastPan;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(TableView old) {
    super.didUpdateWidget(old);
    if (old.skin.id != widget.skin.id) _loadImage();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final skin = widget.skin;
    final ui.Image image;
    if (skin.style != null) {
      // Rasterise the vector table once, well above screen resolution.
      const raster = Size(2400, 1404);
      final recorder = ui.PictureRecorder();
      paintProTable(Canvas(recorder), raster, skin.style!);
      final picture = recorder.endRecording();
      image = picture.toImageSync(raster.width.toInt(), raster.height.toInt());
      picture.dispose();
    } else {
      final data = await rootBundle.load(skin.asset!);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      image = (await codec.getNextFrame()).image;
    }
    if (!mounted || widget.skin.id != skin.id) {
      image.dispose();
      return;
    }
    final previous = _image;
    setState(() => _image = image);
    previous?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      TableProjection projection() => TableProjection(size, c.viewRotated);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final w = projection().toWorld(d.localPosition);
          // A tap on (or near) a ball picks it as the target when allowed
          // and aims at its centre; anywhere else just aims there.
          Ball? near;
          for (final b in c.world.balls) {
            if (b.pocketed || b.number == 0) continue;
            final dist = b.pos.distanceTo(w);
            if (dist < 34 && (near == null || dist < near.pos.distanceTo(w))) near = b;
          }
          if (near != null) {
            c.selectBall(near.number);
            c.aimAt(near.pos);
            return;
          }
          for (var i = 0; i < TableGeometry.pockets.length; i++) {
            if (TableGeometry.pockets[i].aim.distanceTo(w) < 60 && c.tapPocket(i)) return;
          }
          c.aimAt(w);
        },
        onPanStart: (d) {
          final w = projection().toWorld(d.localPosition);
          _draggingCue = c.canPlaceCue && w.distanceTo(c.world.cue.pos) < 45;
          _lastPan = d.localPosition;
        },
        onPanUpdate: (d) {
          final p = projection();
          if (_draggingCue) {
            c.moveCue(p.toWorld(d.localPosition));
          } else if (_lastPan != null) {
            // Rotate the aim by the angle the finger sweeps around the cue
            // ball: far from the ball this gives very fine control.
            final cue = p.toLocal(c.world.cue.pos);
            final a = _lastPan! - cue, b = d.localPosition - cue;
            if (a.distance > 12 && b.distance > 12) {
              var delta = b.direction - a.direction;
              if (delta > pi) delta -= 2 * pi;
              if (delta < -pi) delta += 2 * pi;
              c.nudgeAim(delta);
            }
          }
          _lastPan = d.localPosition;
        },
        onPanEnd: (_) {
          _draggingCue = false;
          _lastPan = null;
        },
        child: RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: _TablePainter(c, _image),
          ),
        ),
      );
    });
  }
}

class _TablePainter extends CustomPainter {
  _TablePainter(this.c, this.image) : super(repaint: c.frame);

  final ShotTable c;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final perf = Perf.begin();
    _paint(canvas, size);
    Perf.end('tablePaint', perf);
  }

  void _paint(Canvas canvas, Size size) {
    final proj = TableProjection(size, c.viewRotated);
    final rect = Offset.zero & size;
    if (image != null) {
      canvas.save();
      if (c.viewRotated) {
        canvas.translate(size.width, size.height);
        canvas.rotate(pi);
      }
      canvas.drawImageRect(
        image!,
        Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)),
          Paint()..color = const Color(0xFF0B4FA8));
    }

    final world = c.world;
    final r = TableGeometry.ballRadius * proj.scale;
    final aiming = (c.showAimGuide || c.showRemoteCue) && !world.cue.pocketed;
    final target = c.targetBall;
    final pulse = 0.5 + 0.5 * sin(c.frame.value / 9);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = AppColors.active.withValues(alpha: 0.75);
    for (final n in c.highlightBalls) {
      if (n != target && !world.balls[n].pocketed) {
        canvas.drawCircle(proj.toLocal(world.balls[n].pos), r + 3, ring);
      }
    }
    if (target != null && !world.balls[target].pocketed) {
      canvas.drawCircle(
        proj.toLocal(world.balls[target].pos),
        r + 4 + pulse * 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AppColors.gold,
      );
    }
    final called = c.calledPocket;
    if (called != null) {
      canvas.drawCircle(
        proj.toLocal(TableGeometry.pockets[called].aim),
        r * 2.2 + pulse * 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = AppColors.gold,
      );
    }

    if (aiming) _paintGuide(canvas, proj, r, target);

    for (final sink in c.sinking) {
      final t = ((c.time - sink.start) / SinkingBall.seconds).clamp(0.0, 1.0);
      final from = proj.toLocal(sink.from);
      final to = proj.toLocal(TableGeometry.pockets[sink.pocket].center);
      paintBall(canvas, Offset.lerp(from, to, t)!, r * (1 - 0.65 * t), sink.number, shadow: false);
    }
    for (final b in world.balls) {
      if (!b.pocketed) paintBall(canvas, proj.toLocal(b.pos), r, b.number);
    }

    if (aiming) {
      _paintCue(canvas, proj, r);
      if (c.showBallInHand) {
        canvas.drawCircle(
          proj.toLocal(world.cue.pos),
          r + 7 + pulse * 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white70,
        );
      }
    }
  }

  void _paintGuide(Canvas canvas, TableProjection proj, double r, int? target) {
    final world = c.world;
    final hit = world.predict(c.aimAngle);
    final from = proj.toLocal(world.cue.pos);
    final ghost = proj.toLocal(hit.ghost);
    final wrong = hit.hitBall != null && c.isWrongContact(hit.hitBall!);
    final color = wrong ? AppColors.danger : Colors.white;
    // White line with a dark edge, readable on any cloth colour.
    final edge = Paint()
      ..color = const Color(0xB3000000)
      ..strokeWidth = r * 0.3
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = color
      ..strokeWidth = r * 0.16
      ..strokeCap = StrokeCap.round;
    void stroke(Offset a, Offset b) {
      canvas.drawLine(a, b, edge);
      canvas.drawLine(a, b, line);
    }

    final dir = proj.dir(Vec2.fromAngle(c.aimAngle));
    stroke(from + dir * (r + 2), ghost - dir * r);
    canvas.drawCircle(
        ghost,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.3
          ..color = const Color(0xB3000000));
    canvas.drawCircle(
        ghost,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.16
          ..color = color);
    if (hit.hitBall != null) {
      canvas.drawCircle(
        proj.toLocal(world.balls[hit.hitBall!].pos),
        r + 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..color = const Color(0xFFFFD54A),
      );
    }
    if (hit.targetDir != null) {
      final ballPos = proj.toLocal(world.balls[hit.hitBall!].pos);
      final t = proj.dir(hit.targetDir!);
      stroke(ballPos + t * r, ballPos + t * (r * 5.5));
      if (hit.cueDir != null) {
        final d = proj.dir(hit.cueDir!);
        stroke(ghost + d * r, ghost + d * (r * 3));
      }
    }
  }

  void _paintCue(Canvas canvas, TableProjection proj, double r) {
    final tip = proj.toLocal(c.world.cue.pos);
    final back = proj.dir(Vec2.fromAngle(c.aimAngle)) * -1;
    final start = tip + back * (r + 5 + c.power * r * 7);
    paintCueStick(canvas, start, back, r * 30, r, CueStyle.of(c.cueId));
  }

  @override
  bool shouldRepaint(_TablePainter old) => old.image != image || old.c != c;
}
