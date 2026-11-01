import 'package:flutter/material.dart';

import 'design/design_colors.dart';
import 'design/design_typography.dart';

/// Palette and type taken from the client's game-screen mockups: dark slate
/// room, indigo-framed tiles, green active ring, gold coins.
class AppColors {
  static const background = DesignColors.appBackground;
  static const backgroundAlt = DesignColors.appBackgroundAlt;
  static const panel = DesignColors.appPanel;
  static const frame = DesignColors.appFrame;
  static const frameLight = DesignColors.appFrameLight;
  static const active = DesignColors.appActive;
  static const gold = DesignColors.appGold;
  static const danger = DesignColors.appDanger;
  static const text = DesignColors.appText;
  static const textDim = DesignColors.appTextDim;
  static const cardBack = DesignColors.cardBack;
}

class AppText {
  static const display = DesignTypography.displayFont;
  static const card = DesignTypography.cardFont;

  static TextStyle label(double size, {Color color = AppColors.text, FontWeight weight = FontWeight.w700}) =>
      DesignTypography.label(size, color: color, weight: weight);
}

/// Shared surface for panels, pills and list rows: a soft top-lit gradient
/// with an indigo rim.
BoxDecoration panelDecoration({
  double radius = 18,
  Color border = AppColors.frame,
  double borderWidth = 2,
  double opacity = 0.94,
  Color? glow,
}) =>
    BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF24242F).withValues(alpha: opacity),
          const Color(0xFF131319).withValues(alpha: opacity),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border, width: borderWidth),
      boxShadow: [
        const BoxShadow(color: Color(0x80000000), blurRadius: 14, offset: Offset(0, 6)),
        if (glow != null) BoxShadow(color: glow.withValues(alpha: 0.35), blurRadius: 26),
      ],
    );

ThemeData buildAppTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: AppText.display,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.active,
        secondary: AppColors.gold,
        surface: AppColors.panel,
        error: AppColors.danger,
      ),
      useMaterial3: true,
    );
