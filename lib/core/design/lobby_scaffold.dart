import 'package:flutter/material.dart';

import '../../features/duel/duel_chrome.dart';
import '../duel_ui.dart';
import 'design_layout.dart';
import 'design_spacing.dart';

/// Standard lobby page chrome: top bar, optional three-column body, bottom nav row.
class LobbyScaffold extends StatelessWidget {
  const LobbyScaffold({
    super.key,
    this.topBar = const DuelTopBar(),
    this.title,
    this.leftRail,
    required this.center,
    this.rightRail,
    this.bottomLeading,
    this.bottomNav,
    this.centerPadding = const EdgeInsets.only(top: DesignSpacing.x3),
  });

  final Widget topBar;
  final Widget? title;
  final Widget? leftRail;
  final Widget center;
  final Widget? rightRail;
  final Widget? bottomLeading;
  final Widget? bottomNav;
  final EdgeInsets centerPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        topBar,
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(DesignSpacing.screenEdge, DesignSpacing.x4, DesignSpacing.screenEdge, 0),
            child: title!,
          ),
        ],
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              DesignSpacing.screenEdge,
              centerPadding.top,
              DesignSpacing.screenEdge,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leftRail != null) ...[
                  SizedBox(width: DesignLayout.homeLeftRailWidth, child: leftRail!),
                  const SizedBox(width: DesignSpacing.x4),
                ],
                Expanded(child: center),
                if (rightRail != null) ...[
                  const SizedBox(width: DesignSpacing.x4),
                  SizedBox(width: DesignLayout.homeRightRailWidth, child: rightRail!),
                ],
              ],
            ),
          ),
        ),
        if (bottomLeading != null || bottomNav != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignSpacing.screenEdge,
              DesignSpacing.x2,
              DesignSpacing.screenEdge,
              DesignLayout.bottomBarInset,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?bottomLeading,
                if (bottomLeading != null && bottomNav != null) const SizedBox(width: DesignSpacing.navGap),
                ?(bottomNav == null ? null : Expanded(child: bottomNav!)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Back control used on hub sub-screens.
class LobbyBackNav extends StatelessWidget {
  const LobbyBackNav({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => NavTile(icon: Icons.reply_rounded, label: label, onTap: onTap);
}
