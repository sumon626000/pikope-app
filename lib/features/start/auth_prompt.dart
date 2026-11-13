import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../l10n/strings.dart';
import '../duel/lobby_data.dart';
import '../online/session.dart';
import 'login_auth_panel.dart';

/// True when the player linked a mobile login (not a guest session).
bool hasRegisteredAccount(WidgetRef ref) {
  final session = ref.read(sessionProvider);
  return session.signedIn && !session.isGuest;
}

/// Header wallet when registered; null while browsing without an account.
int? lobbyDisplayCoins(WidgetRef ref) {
  if (!hasRegisteredAccount(ref)) return null;
  return ref.watch(sessionProvider).walletCoins;
}

bool _loginPopupOpen = false;

/// Waits for a saved token to hydrate session (fast Shop/+ tap right after splash).
Future<bool> _restoreRegisteredIfSaved(WidgetRef ref) async {
  if (hasRegisteredAccount(ref)) return true;
  if (ref.read(settingsProvider).authToken.isEmpty) return false;
  final notifier = ref.read(sessionProvider.notifier);
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      if (await notifier.tryRestoreExistingSession() &&
          hasRegisteredAccount(ref)) {
        return true;
      }
    } catch (_) {}
    if (attempt < 3) {
      await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
    }
  }
  return hasRegisteredAccount(ref);
}

/// Small lobby-style prompt (440px) — Cancel or continue to the compact sign-in form.
Future<bool> _showLoginRequiredPrompt(
  BuildContext context,
  WidgetRef ref,
) async {
  final t = ref.read(stringsProvider);
  final go = await showDuelDialog<bool>(
    context,
    barrierColor: DesignAuth.overlayScrim,
    barrierDismissible: true,
    builder: (ctx) => PcDialog(
      title: t.loginRequiredTitle,
      width: 820,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.login_rounded,
            color: DesignColors.pcGold,
            size: 72,
            shadows: [
              Shadow(
                color: Color(0x99000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            t.loginRequiredBody,
            textAlign: TextAlign.center,
            style: pcText(30, weight: FontWeight.w500).copyWith(height: 1.35),
          ),
          const SizedBox(height: 28),
          PcButton(
            label: t.signUpOrLogin,
            width: 640,
            height: 84,
            fontSize: 34,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: 14),
          PcButton(
            label: t.cancel,
            style: PcButtonStyle.gray,
            width: 640,
            height: 76,
            fontSize: 30,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
      ),
    ),
  );
  return go == true;
}

/// Compact sign-in overlay in real viewport pixels (scrolls on short landscape).
Future<bool> showLoginAuthPopup(BuildContext context, WidgetRef ref) async {
  if (_loginPopupOpen) return false;
  _loginPopupOpen = true;
  try {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierColor: DesignAuth.overlayScrim,
      barrierDismissible: true,
      builder: (dialogContext) {
        final mq = MediaQuery.of(dialogContext);
        final inset = mq.padding;
        final maxW = mq.size.width - inset.horizontal - 20;
        final maxH = mq.size.height - inset.vertical - 12;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.fromLTRB(
            10 + inset.left,
            6 + inset.top,
            10 + inset.right,
            6 + inset.bottom,
          ),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(DesignAuth.loginPopupMaxWidth, maxW),
              maxHeight: maxH,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Material(
                  color: Colors.transparent,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: LoginAuthPanel(
                      compact: true,
                      onAuthenticated: () =>
                          Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      tooltip: MaterialLocalizations.of(
                        dialogContext,
                      ).closeButtonTooltip,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return ok == true;
  } finally {
    _loginPopupOpen = false;
  }
}

/// Ask for sign-up / login when a feature needs a saved account. Returns true if registered.
Future<bool> requireRegisteredAccount(
  BuildContext context,
  WidgetRef ref,
) async {
  if (await _restoreRegisteredIfSaved(ref)) return true;
  if (!context.mounted) return false;
  if (!await _showLoginRequiredPrompt(context, ref)) return false;
  if (!context.mounted) return false;
  final ok = await showLoginAuthPopup(context, ref);
  if (ok && hasRegisteredAccount(ref)) {
    ref.read(lobbyProvider.notifier).refresh();
    return true;
  }
  return false;
}
