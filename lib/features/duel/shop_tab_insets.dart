import 'package:flutter/material.dart';

import '../../core/design/design_layout.dart';

/// Shared padding for Shop tab scroll areas (Buy, Transfer, Redeem, History).
abstract final class ShopTabInsets {
  static const scroll = EdgeInsets.fromLTRB(16, 14, 16, 18);
  static const scrollPhone = EdgeInsets.fromLTRB(10, 6, 10, 8);
  static const scrollPhoneFit = EdgeInsets.fromLTRB(8, 4, 8, 6);

  static EdgeInsets forViewport(BuildContext context) =>
      DesignBreakpoints.phoneLike(context) ? scrollPhone : scroll;
}
