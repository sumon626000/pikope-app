import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_theme.dart';
import '../../../l10n/strings.dart';
import '../../../core/duel_ui.dart';
import '../../../core/widgets.dart';
import '../game_controller.dart';

class Scrim extends StatelessWidget {
  const Scrim({super.key, required this.child, this.confetti = false});

  final Widget child;
  final bool confetti;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: GestureDetector(
          onTap: () {},
          child: Container(
            decoration: const BoxDecoration(
              // The shadow paints under the box as well, so it alone dims the
              // canvas and spills past it to cover wide screens edge to edge.
              boxShadow: [BoxShadow(color: Color(0xCC000000), spreadRadius: 900)],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (confetti) const Positioned.fill(child: IgnorePointer(child: _Confetti())),
                child,
              ],
            ),
          ),
        ),
      );
}

class _Confetti extends StatefulWidget {
  const _Confetti();

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ConfettiPainter(_controller));
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  static const _colors = [AppColors.gold, AppColors.active, Color(0xFFFF4D8D), Color(0xFF4DA3FF), Colors.white];
  static final _pieces = [
    for (final r in [Random(7)])
      for (var i = 0; i < 90; i++)
        (x: r.nextDouble(), phase: r.nextDouble(), speed: 0.6 + r.nextDouble() * 0.8,
         sway: r.nextDouble() * 2 * pi, size: 8 + r.nextDouble() * 10, color: i % _colors.length)
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _pieces) {
      final fall = (t.value * p.speed + p.phase) % 1;
      final x = p.x * size.width + sin(fall * 2 * pi * 2 + p.sway) * 30;
      final y = fall * (size.height + 40) - 20;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(fall * 2 * pi * 3 + p.sway);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
        Paint()..color = _colors[p.color],
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}

class OverlayPanel extends StatelessWidget {
  const OverlayPanel({super.key, required this.child, this.width = 760, this.borderColor = AppColors.frame});

  final Widget child;
  final double width;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(32),
        decoration: panelDecoration(radius: 28, border: borderColor, borderWidth: 4, opacity: 1, glow: borderColor),
        child: child,
      );
}

/// Pass & play: hides the table state until the next player holds the device.
class HandoffOverlay extends ConsumerWidget {
  const HandoffOverlay({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final p = controller.current;
    return Scrim(
      child: OverlayPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FramedTile(size: 130, child: AvatarImage(p.avatar, size: 130)),
            const SizedBox(height: 18),
            Text(t.passDeviceTo, style: AppText.label(20, color: AppColors.textDim)),
            const SizedBox(height: 6),
            Text(p.name.toUpperCase(), style: AppText.label(40, weight: FontWeight.w900)),
            const SizedBox(height: 26),
            GameButton(label: t.imReady, width: 320, onPressed: controller.confirmHandoff),
          ],
        ),
      ),
    );
  }
}

class GameOverOverlay extends ConsumerWidget {
  const GameOverOverlay({
    super.key,
    required this.controller,
    required this.reward,
    required this.onRematch,
    required this.onHome,
    this.rematchLabel = 'REMATCH',
  });

  final GameController controller;
  final int? reward;
  /// Null hides the button (online matches restart from the lobby).
  final VoidCallback? onRematch;
  final String rematchLabel;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final c = controller;
    final winner = c.players[c.state.winner!];
    Widget cell(String text, {double flex = 1, Color color = AppColors.text, bool left = false}) =>
        Expanded(
          flex: (flex * 10).round(),
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: left ? TextAlign.left : TextAlign.center,
              style: AppText.label(18, color: color)),
        );
    return Scrim(
      confetti: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        builder: (_, t, child) => Transform.translate(offset: Offset(0, 120 * t), child: child),
        child: OverlayPanel(
          width: 980,
          borderColor: AppColors.gold,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FramedTile(
                    size: 130,
                    frameColor: AppColors.gold,
                    child: AvatarImage(winner.avatar, size: 130),
                  ),
                  const SizedBox(width: 28),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.emoji_events_rounded, color: AppColors.gold, size: 44),
                        const SizedBox(width: 10),
                        Text(t.winner, style: AppText.label(26, color: AppColors.gold)),
                      ]),
                      Text(winner.name.toUpperCase(), style: AppText.label(48, weight: FontWeight.w900)),
                      if (reward != null && reward! > 0)
                        Text('+${formatPicoCoins(reward!)}', style: AppText.label(20, color: AppColors.gold)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(children: [
                cell(t.playerCol, flex: 2.2, color: AppColors.textDim, left: true),
                cell(t.shotsCol, color: AppColors.textDim),
                cell(t.ballsCol, color: AppColors.textDim),
                cell(t.foulsCol, color: AppColors.textDim),
                cell(t.penaltyCol, color: AppColors.textDim),
                cell(t.leftCol, color: AppColors.textDim),
              ]),
              const Divider(color: AppColors.frame, height: 18),
              for (final i in c.state.turnOrder)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    cell(c.players[i].name.toUpperCase(),
                        flex: 2.2,
                        left: true,
                        color: i == c.state.winner ? AppColors.gold : AppColors.text),
                    cell('${c.players[i].stats.shots}'),
                    cell('${c.players[i].stats.ballsCompleted}'),
                    cell('${c.players[i].stats.fouls}'),
                    cell('${c.players[i].stats.penaltyCards}'),
                    cell('${c.players[i].pendingCount}'),
                  ]),
                ),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onRematch != null) ...[
                    GameButton(label: rematchLabel, icon: Icons.replay_rounded, width: 300, onPressed: onRematch),
                    const SizedBox(width: 24),
                  ],
                  GameButton(
                    label: t.home,
                    icon: Icons.home_rounded,
                    width: 300,
                    color: AppColors.frame,
                    onPressed: onHome,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PauseOverlay extends ConsumerWidget {
  const PauseOverlay({
    super.key,
    required this.soundOn,
    required this.onResume,
    required this.onToggleSound,
    required this.onRules,
    required this.onQuit,
  });

  final bool soundOn;
  final VoidCallback onResume;
  final VoidCallback onToggleSound;
  final VoidCallback onRules;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return Scrim(
      child: OverlayPanel(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.menu, style: AppText.label(34, weight: FontWeight.w900)),
            const SizedBox(height: 24),
            GameButton(label: t.resume, icon: Icons.play_arrow_rounded, width: 400, onPressed: onResume),
            const SizedBox(height: 14),
            GameButton(
              label: t.soundOnLabel(soundOn),
              icon: soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              width: 400,
              color: AppColors.frame,
              onPressed: onToggleSound,
            ),
            const SizedBox(height: 14),
            GameButton(
              label: t.howToPlay,
              icon: Icons.menu_book_rounded,
              width: 400,
              color: AppColors.frame,
              onPressed: onRules,
            ),
            const SizedBox(height: 14),
            GameButton(
              label: t.quitMatch,
              icon: Icons.logout_rounded,
              width: 400,
              color: AppColors.danger,
              onPressed: onQuit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Online play: covers the table while the server cannot be reached, and
/// confirms briefly when the connection is back.
class ConnectionStatusLayer extends StatefulWidget {
  const ConnectionStatusLayer({super.key, required this.offline, required this.onLeave});

  final ValueListenable<bool> offline;
  final VoidCallback onLeave;

  @override
  State<ConnectionStatusLayer> createState() => _ConnectionStatusLayerState();
}

class _ConnectionStatusLayerState extends State<ConnectionStatusLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  bool _wasOffline = false;
  bool _showBack = false;
  int _backToken = 0;

  @override
  void initState() {
    super.initState();
    _wasOffline = widget.offline.value;
    widget.offline.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    final offline = widget.offline.value;
    if (offline == _wasOffline) return;
    _wasOffline = offline;
    final token = ++_backToken;
    setState(() => _showBack = !offline);
    if (!offline) {
      Future<void>.delayed(const Duration(milliseconds: 2200), () {
        if (mounted && token == _backToken) setState(() => _showBack = false);
      });
    }
  }

  @override
  void dispose() {
    widget.offline.removeListener(_changed);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final t = ref.watch(stringsProvider);
        if (widget.offline.value) {
          return Scrim(
            child: OverlayPanel(
              width: 720,
              borderColor: AppColors.gold,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 132,
                    height: 132,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, child) => CustomPaint(painter: _SignalPainter(_pulse.value), child: child),
                      child: const Center(child: Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.gold)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(t.connectionLost, style: AppText.label(34, weight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, _) => Text(
                      t.reconnectingDots(1 + (_pulse.value * 3).floor().clamp(0, 2)),
                      style: AppText.label(22, color: AppColors.gold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.connectionLostBody,
                    textAlign: TextAlign.center,
                    style: AppText.label(15, color: AppColors.textDim, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.shotClockExitHint,
                    textAlign: TextAlign.center,
                    style: AppText.label(13, color: AppColors.textDim, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),
                  GameButton(
                    label: t.exitToHome,
                    icon: Icons.home_rounded,
                    width: 360,
                    color: AppColors.frame,
                    onPressed: widget.onLeave,
                  ),
                ],
              ),
            ),
          );
        }
        if (_showBack) {
          return Positioned(
            top: 150,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: AppColors.active, width: 3),
                    boxShadow: const [BoxShadow(color: Color(0x662EE84F), blurRadius: 18)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_rounded, color: AppColors.active, size: 30),
                      const SizedBox(width: 12),
                      Text(t.backOnline, style: AppText.label(22, color: AppColors.active, weight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Rings spreading out from the icon, like a signal being searched for.
class _SignalPainter extends CustomPainter {
  _SignalPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    canvas.drawCircle(center, maxR * 0.5, Paint()..color = const Color(0x22FFC928));
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      canvas.drawCircle(
        center,
        maxR * (0.5 + 0.5 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = AppColors.gold.withValues(alpha: (1 - p) * 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(_SignalPainter old) => old.t != t;
}
