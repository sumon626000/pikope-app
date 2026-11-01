import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../duel_ui.dart';
import 'design_colors.dart';
import 'design_layout.dart';
import 'design_spacing.dart';
import 'design_typography.dart';

/// Auth, settings forms, and [PageFrame] widths.
abstract final class DesignAuth {
  static const pageFrameMaxWidth = 980.0;
  static const pageFrameFormMaxWidth = 620.0;
  static const forgotPasswordMaxWidth = 560.0;

  static const loginFormMaxWidth = 860.0;
  static const loginPanelPadding = EdgeInsets.fromLTRB(48, 40, 48, 36);
  static const loginPanelRadius = 32.0;

  /// [SettingsScreen] on [DuelPage] — centered column, panel grid, footer actions.
  static const settingsContentMaxWidth = 1340.0;
  static const settingsPanelMinHeight = 108.0;
  static const settingsPanelGap = 12.0;
  static const settingsSectionGap = 14.0;
  static const settingsActionHeight = 50.0;
  static const settingsActionFontSize = 14.0;
  static const settingsActionColumnsWide = 3;
  static const settingsActionColumnsPhone = 2;

  static const overlayScrim = Color(0xB3000000);
  static const dialogChooserWidth = 460.0;
  static const dialogPracticeWidth = 520.0;
  static const dailyBonusDialogWidth = 640.0;

  static const fieldFill = DesignColors.appPanel;
  static const fieldBorder = DesignColors.appFrame;
  static const fieldFillLobby = Color(0xFF0E1430);
  static const fieldFillLogin = Color(0xFF16161B);

  static InputDecoration fieldDecoration(
    String label, {
    IconData? icon,
    bool dense = false,
  }) {
    final radius = BorderRadius.circular(DesignRadii.md);
    final border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: fieldBorder, width: 2),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontFamily: DesignTypography.displayFont,
        fontSize: dense ? 14 : 26,
        color: DesignColors.appTextDim,
      ),
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: DesignColors.appTextDim, size: dense ? 22 : 36),
      filled: true,
      fillColor: dense ? fieldFillLobby : fieldFillLogin,
      counterText: '',
      contentPadding: EdgeInsets.symmetric(
        horizontal: dense ? 12 : 22,
        vertical: dense ? 12 : 26,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: DesignColors.appActive, width: 2),
      ),
    );
  }
}

/// Standard rimmed dialog body for auth / confirm prompts ([showDuelDialog] child).
class DesignPromptDialog extends StatelessWidget {
  const DesignPromptDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
    this.rim = DesignColors.duelGold,
    this.width = DesignLayout.dialogMaxWidth,
  });

  final Widget icon;
  final String title;
  final String body;
  final List<Widget> actions;
  final Color rim;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(DesignSpacing.x5),
        decoration: duelPanel(rim: rim),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: DesignSpacing.x2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.label(18, weight: FontWeight.w900),
            ),
            const SizedBox(height: DesignSpacing.x2),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: DesignTypography.displayFont,
                fontSize: 14,
                height: 1.4,
                color: DesignColors.silver,
              ),
            ),
            SizedBox(
              height: actions.length == 1 ? DesignSpacing.x4 : DesignSpacing.x5,
            ),
            if (actions.length == 1)
              actions.first
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: DesignSpacing.x3),
                    actions[i],
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
