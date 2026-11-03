import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/design/design.dart';
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
Future<bool> _showLoginRequiredPrompt(BuildContext context, WidgetRef ref) async {
  final t = ref.read(stringsProvider);
  final go = await showDuelDialog<bool>(
    context,
    barrierColor: DesignAuth.overlayScrim,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: DesignAuth.loginPromptWidth,
        padding: const EdgeInsets.all(22),
        decoration: duelPanel(rim: DuelColors.gold),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.login_rounded, color: DuelColors.gold, size: 40),
            const SizedBox(height: 10),
            Text(
              t.loginRequiredTitle,
              textAlign: TextAlign.center,
              style: AppText.label(18, weight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              t.loginRequiredBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'sans-serif',
                fontSize: 14,
                height: 1.4,
                color: DuelColors.silver,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DuelButton(
                  label: t.cancel,
                  width: 140,
                  height: 42,
                  fontSize: 15,
                  color: DuelColors.blue,
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
                const SizedBox(width: 12),
                DuelButton(
                  label: t.signUpOrLogin,
                  width: 220,
                  height: 42,
                  fontSize: 14,
                  color: DuelColors.green,
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ],
        ),
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
                    padding: const EdgeInsets.only(top: 2, right: 28),
                    child: LoginAuthPanel(
                      compact: true,
                      onAuthenticated: () =>
                          Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      tooltip: MaterialLocalizations.of(
                        dialogContext,
                      ).closeButtonTooltip,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: DuelColors.silver,
                        size: 24,
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
