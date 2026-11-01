import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'design_colors.dart';

/// Match canvas layout (1950×900) — same as [DesignCanvas.tableSize] in widgets.dart.
abstract final class DesignGameplay {
  static const canvasWidth = 1950.0;
  static const canvasHeight = 900.0;
  static const canvasSize = Size(canvasWidth, canvasHeight);

  /// Pool table play area on the match canvas.
  static const poolTableRect = Rect.fromLTWH(339, 150, 1272, 744);

  static const ludoBoardSize = 820.0;
  static const ludoBoardLeft = (canvasWidth - ludoBoardSize) / 2;
  static const ludoBoardTop = (canvasHeight - ludoBoardSize) / 2;

  static const carromBoardSize = 832.0;
  static const carromBoardTop = 10.0;
  static const carromBoardLeft = (canvasWidth - carromBoardSize) / 2;

  static const carromSliderWidth = 560.0;
  static const carromSliderHeight = 46.0;
  static const carromSliderLeft = (canvasWidth - carromSliderWidth) / 2;
  static const carromSliderTop = carromBoardTop + carromBoardSize + 10;

  /// In-match HUD chrome.
  static const menuTabLeft = 64.0;
  static const prizeTileLeft = 20.0;
  static const prizeTileTop = 58.0;

  /// Pause menu panel on the table canvas.
  static const pausePanelWidth = 520.0;

  /// Full-screen overlays (reveal, jackpot, result).
  static const overlayScrimReveal = Color(0x8C000000);
  static const overlayScrimJackpot = Color(0xA6000000);
  static const resultGradient = [
    Color(0xFF16205A),
    Color(0xFF0A0E26),
    Color(0xFF05070F),
  ];

  static const resultSeatLarge = 260.0;
  static const resultSeatCompact = 230.0;
  static const resultVsWide = 120.0;
  static const resultVsFourPlayer = 96.0;
  static const resultPlayerGap = 34.0;

  static const hintActive = Color(0xFFFFE45C);
  static const hintIdle = Color(0xB3FFFFFF);

  static const toastFill = Color(0xE6101A3A);
  static const toastBorderNeutral = Color(0xFFF2C230);
  static const toastBorderGood = DesignColors.duelGreen;
  static const toastBorderBad = DesignColors.duelRed;
  static const toastRadius = 30.0;
  static const toastPaddingH = 28.0;
  static const toastPaddingV = 12.0;

  static const jackpotWheelSize = 640.0;
  static const revealBallSize = 170.0;
}

/// Center toast shown over ludo / carrom boards.
class GameplayToastBanner extends StatelessWidget {
  const GameplayToastBanner({
    super.key,
    required this.lines,
    this.good,
    this.primarySize = 30,
    this.secondarySize = 20,
  });

  final List<String> lines;
  final bool? good;
  final double primarySize;
  final double secondarySize;

  @override
  Widget build(BuildContext context) {
    final rim = switch (good) {
      true => DesignGameplay.toastBorderGood,
      false => DesignGameplay.toastBorderBad,
      null => DesignGameplay.toastBorderNeutral,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignGameplay.toastPaddingH,
        vertical: DesignGameplay.toastPaddingV,
      ),
      decoration: BoxDecoration(
        color: DesignGameplay.toastFill,
        borderRadius: BorderRadius.circular(DesignGameplay.toastRadius),
        border: Border.all(color: rim, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < lines.length; i++)
            Text(
              lines[i],
              style: AppText.label(
                i == 0 ? primarySize : secondarySize,
                color: i == 0 ? Colors.white : Colors.white70,
                weight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}
