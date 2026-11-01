import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/design/design.dart';
import '../../core/duel_ui.dart';
import '../duel/lobby_data.dart';
import '../online/session.dart';
import 'login_auth_panel.dart';

/// True when the player linked a mobile login (not a guest session).
bool hasRegisteredAccount(WidgetRef ref) {
  final session = ref.read(sessionProvider);
  return session.signedIn && !session.isGuest;
}

/// Header wallet: real balance when registered; local demo (2000) when browsing without login.
int lobbyDisplayCoins(WidgetRef ref) {
  final session = ref.watch(sessionProvider);
  if (session.signedIn && !session.isGuest) return session.walletCoins;
  final local = ref.watch(settingsProvider).coins;
  if (local <= 0) return const AppSettings().coins;
  return local;
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

/// Dismissible sign-in overlay on the current screen (not [showDuelDialog] canvas — that read as a full auth page).
Future<bool> showLoginAuthPopup(BuildContext context, WidgetRef ref) async {
  if (_loginPopupOpen) return false;
  _loginPopupOpen = true;
  try {
    final ok = await showGeneralDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: DesignAuth.overlayScrim,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, _, _) {
        final maxH = MediaQuery.sizeOf(dialogContext).height * 0.88;
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: DesignAuth.loginPopupMaxWidth,
                  maxHeight: maxH,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SingleChildScrollView(
                        child: LoginAuthPanel(
                          compact: true,
                          onAuthenticated: () =>
                              Navigator.of(dialogContext).pop(true),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
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
                              size: 26,
                            ),
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
  final ok = await showLoginAuthPopup(context, ref);
  if (ok && hasRegisteredAccount(ref)) {
    ref.read(lobbyProvider.notifier).refresh();
    return true;
  }
  return false;
}
