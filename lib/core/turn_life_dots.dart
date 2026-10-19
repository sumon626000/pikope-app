import 'package:flutter/material.dart';

/// Three turn warnings: all green at start; each timeout/miss turns one dot red.
/// Three reds means the server ends the match for that player.
class TurnLifeDots extends StatelessWidget {
  const TurnLifeDots({super.key, required this.missed, this.lives = 3, this.size = 10});

  final int missed;
  final int lives;
  final double size;

  static const green = Color(0xFF3FDD5C);
  static const red = Color(0xFFE84C4C);

  @override
  Widget build(BuildContext context) {
    final m = missed.clamp(0, lives);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lives; i++)
          Container(
            width: size,
            height: size,
            margin: EdgeInsets.symmetric(horizontal: size * 0.22),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < m ? red : green,
              border: Border.all(color: const Color(0xFF0B3A1A), width: 1.2),
              boxShadow: i < m
                  ? [BoxShadow(color: red.withValues(alpha: 0.55), blurRadius: 4)]
                  : [BoxShadow(color: green.withValues(alpha: 0.35), blurRadius: 3)],
            ),
          ),
      ],
    );
  }
}
