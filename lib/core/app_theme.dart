import 'package:flutter/material.dart';

/// Palette and type taken from the client's game-screen mockups: dark slate
/// room, indigo-framed tiles, green active ring, gold coins.
class AppColors {
  static const background = Color(0xFF1E1E21);
  static const backgroundAlt = Color(0xFF26262A);
  static const panel = Color(0xFF15151A);
  static const frame = Color(0xFF4A4973);
  static const frameLight = Color(0xFF6C6BA0);
  static const active = Color(0xFF2EE84F);
  static const gold = Color(0xFFFFC928);
  static const danger = Color(0xFFFF4D4D);
  static const text = Color(0xFFF2F2F5);
  static const textDim = Color(0xFF9A9AA8);
  static const cardBack = Color(0xFFD9263E);
}

class AppText {
  // Plain system sans (Roboto on Android) for all UI text: the client asked
  // for an ordinary, readable font, not a stylised one. Ball numbers keep
  // their own display font in ball_painter.dart.
  static const display = 'Roboto';
  static const card = 'DMSerifDisplay';

  static TextStyle label(double size, {Color color = AppColors.text, FontWeight weight = FontWeight.w700}) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: size * 0.01,
        height: 1.15,
      );
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
