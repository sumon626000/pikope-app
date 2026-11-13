import 'package:flutter/material.dart';

import '../duel_ui.dart';
import 'design_colors.dart';
import 'pool_city.dart';
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

  /// Small “sign in required” chooser ([showDuelDialog], canvas-scaled).
  static const loginPromptWidth = 440.0;

  /// Home-overlay sign-in form (step 2 after prompt; not full [LoginScreen] route).
  static const loginPopupMaxWidth = 380.0;
  static const loginPopupPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);
  static const loginPopupRadius = 20.0;

  /// [SettingsScreen] on [DuelPage] — centered column, panel grid, footer actions.
  static const settingsContentMaxWidth = 1340.0;
  static const settingsPanelMinHeight = 108.0;
  static const settingsPanelGap = 12.0;
  static const settingsSectionGap = 14.0;
  static const settingsActionHeight = 50.0;
  static const settingsActionFontSize = 14.0;
  static const settingsActionColumnsWide = 3;
  static const settingsActionColumnsPhone = 2;

  /// Full-viewport settings on phones (no 1600×900 canvas scale).
  static const settingsPhonePaddingH = 14.0;
  static const settingsPhonePaddingBottom = 20.0;
  static const settingsPhoneSectionGap = 12.0;
  static const settingsPhonePanelGap = 10.0;

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
        fontSize: dense ? 14 : 34,
        color: DesignColors.appTextDim,
      ),
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: DesignColors.appTextDim, size: dense ? 22 : 44),
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
    // Pool City dialog: header bar with the title, dark body, action row.
    return PcDialog(
      title: title,
      actions: actions,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme.merge(data: const IconThemeData(size: 90), child: icon),
          const SizedBox(height: 24),
          Text(body, textAlign: TextAlign.center, style: pcText(36, weight: FontWeight.w500).copyWith(height: 1.35)),
        ],
      ),
    );
  }
}

