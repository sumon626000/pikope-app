import 'package:flutter/material.dart';

import 'design_spacing.dart';

/// [DuelPage] shop / history / items layout on the 1600×900 lobby canvas.
abstract final class DesignSecondaryPage {
  static const titleTop = 118.0;
  static const bodyTopDefault = 226.0;
  static const bodyTopExpanded = 168.0;
  static const bodyBottomDefault = 40.0;
  static const bodyBottomExpanded = 12.0;

  static const contentInsetDefaultLeft = 210.0;
  static const contentInsetDefaultRight = 60.0;
  static const contentInsetExpandedLeft = 28.0;
  static const contentInsetExpandedRight = 20.0;
  static const contentInsetSideBackLeft = 188.0;
  static const contentInsetSideBackExpandedLeft = 168.0;

  static const backLeft = DesignSpacing.screenEdge - 2;
  static const backSideLeft = 20.0;

  static double bodyTop({required bool expanded, double? override}) =>
      override ?? (expanded ? bodyTopExpanded : bodyTopDefault);

  static double backTop({required bool expanded, required bool sideBack, double? contentTop}) {
    if (!sideBack) return 0;
    if (contentTop != null) return contentTop - 14;
    return expanded ? 178 : 210;
  }

  static EdgeInsets contentPadding({
    required bool expanded,
    required bool sideBack,
  }) =>
      EdgeInsets.fromLTRB(
        sideBack
            ? (expanded ? contentInsetSideBackExpandedLeft : contentInsetSideBackLeft)
            : (expanded ? contentInsetExpandedLeft : contentInsetDefaultLeft),
        0,
        expanded ? contentInsetExpandedRight : contentInsetDefaultRight,
        expanded ? bodyBottomExpanded : bodyBottomDefault,
      );
}
