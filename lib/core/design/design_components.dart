import 'package:flutter/material.dart';

import '../duel_ui.dart';
import 'design_colors.dart';
import 'design_layout.dart';
import 'design_typography.dart';

/// Primary lobby CTA — [DuelButton] with design-system defaults.
class DesignPrimaryButton extends StatelessWidget {
  const DesignPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = DesignColors.duelGreen,
    this.width = DesignLayout.primaryButtonWidth,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final double width;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DuelButton(
        label: label,
        onPressed: onPressed,
        color: color,
        width: width,
        height: DesignLayout.primaryButtonHeight,
        fontSize: DesignLayout.primaryButtonFontSize,
        icon: icon,
      );
}

/// Secondary / dialog action — compact [DuelButton].
class DesignCompactButton extends StatelessWidget {
  const DesignCompactButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = DesignColors.duelBlue,
    this.width = DesignLayout.compactButtonWidth,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => DuelButton(
        label: label,
        onPressed: onPressed,
        color: color,
        width: width,
        height: DesignLayout.compactButtonHeight,
        fontSize: DesignLayout.compactButtonFontSize,
      );
}

/// Sized box matching standard game-card footprint (content supplied by caller).
class DesignGameCardFrame extends StatelessWidget {
  const DesignGameCardFrame({super.key, required this.child, this.width = DesignLayout.gameCardWidth});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: DesignLayout.gameCardHeight,
        child: child,
      );
}

/// Documents nav tile footprint; use [NavTile] for behavior until Phase 3 migration.
class DesignNavTileSlot extends StatelessWidget {
  const DesignNavTileSlot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: DesignLayout.navTileSize,
        height: DesignLayout.navTileSize,
        child: child,
      );
}

/// Dialog title style aligned with [showDuelMessage].
TextStyle designDialogTitleStyle() =>
    DesignTypography.label(DesignTypography.dialogTitle, weight: FontWeight.w900);
