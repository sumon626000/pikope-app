import 'package:flutter/material.dart';

import 'design_colors.dart';

/// Type scale and font families for the design system.
abstract final class DesignTypography {
  static const displayFont = 'Roboto';
  static const cardFont = 'DMSerifDisplay';

  /// UI labels (matches legacy [AppText.label]).
  static TextStyle label(
    double size, {
    Color color = DesignColors.appText,
    FontWeight weight = FontWeight.w700,
  }) =>
      TextStyle(
        fontFamily: displayFont,
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: size * 0.01,
        height: 1.15,
      );

  // Common lobby sizes (1600×900 design coordinates)
  static const navLabel = 15.0;
  static const dialogTitle = 18.0;
  static const primaryButton = 26.0;
  static const compactButton = 15.0;
  static const gameCardTitle = 40.0;
  static const gameCardSub = 15.0;
}
