import 'package:flutter/material.dart';

import '../../core/design/design_layout.dart';
import 'shop_tab_insets.dart';

/// Viewport-fitting metrics for Pico Coin on phone landscape (UI only).
abstract final class ShopPhoneLayout {
  static bool phone(BuildContext context) =>
      DesignBreakpoints.phoneLike(context);

  static EdgeInsets tabPadding(BuildContext context) =>
      ShopTabInsets.forViewport(context);

  /// BUY tab: always 3-up on phone landscape width.
  static int buyColumns(double width) => width >= 420 ? 3 : 2;

  static double tutorialBlockHeight(BuildContext context, {required bool visible}) {
    if (!visible) return 0;
    return phone(context) ? 46 : 80;
  }

  static double gridGap(BuildContext context) => phone(context) ? 6 : 10;

  static double cardHeightForRows({
    required double viewportHeight,
    required int rowCount,
    required double gap,
    required double reservedTop,
    double safety = 0,
  }) {
    if (rowCount <= 0 || !viewportHeight.isFinite) return 120;
    final avail =
        viewportHeight - reservedTop - (rowCount - 1) * gap - safety;
    return (avail / rowCount).clamp(68.0, 220.0);
  }
}
