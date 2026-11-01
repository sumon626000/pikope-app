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

/// Dismissible sign-in overlay on top of the current screen (home stays visible).
Future<bool> showLoginAuthPopup(BuildContext context, WidgetRef ref) async {
  final ok = await showDuelDialog<bool>(
    context,
    barrierColor: DesignAuth.overlayScrim,
    barrierDismissible: true,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: DesignAuth.loginPopupMaxWidth,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.88,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: Colors.transparent,
                child: SingleChildScrollView(
                  child: LoginAuthPanel(
                    compact: true,
                    onAuthenticated: () =>
                        Navigator.of(dialogContext).pop(true),
                  ),
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
}

/// Ask for sign-up / login when a feature needs a saved account. Returns true if registered.
Future<bool> requireRegisteredAccount(
  BuildContext context,
  WidgetRef ref,
) async {
  if (hasRegisteredAccount(ref)) return true;
  if (ref.read(settingsProvider).authToken.isNotEmpty) {
    try {
      if (await ref
          .read(sessionProvider.notifier)
          .tryRestoreExistingSession()) {
        if (hasRegisteredAccount(ref)) return true;
      }
    } catch (_) {}
  }
  if (!context.mounted) return false;
  final ok = await showLoginAuthPopup(context, ref);
  if (ok && hasRegisteredAccount(ref)) {
    ref.read(lobbyProvider.notifier).refresh();
    return true;
  }
  return false;
}
