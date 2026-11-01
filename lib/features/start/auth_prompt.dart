import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../core/duel_ui.dart';
import '../duel/lobby_data.dart';
import '../online/session.dart';
import '../../l10n/strings.dart';
import 'login_screen.dart';

/// True when the player linked a mobile login (not a guest session).
bool hasRegisteredAccount(WidgetRef ref) {
  final session = ref.read(sessionProvider);
  return session.signedIn && !session.isGuest;
}

/// Ask for sign-up / login when a feature needs a saved account. Returns true if registered.
Future<bool> requireRegisteredAccount(BuildContext context, WidgetRef ref) async {
  if (hasRegisteredAccount(ref)) return true;
  final t = ref.read(stringsProvider);
  final go = await showDuelDialog<bool>(
    context,
    builder: (ctx) => DesignPromptDialog(
      icon: const Icon(Icons.login_rounded, color: DuelColors.gold, size: 40),
      title: t.loginRequiredTitle,
      body: t.loginRequiredBody,
      actions: [
        DesignCompactButton(label: t.cancel, onPressed: () => Navigator.of(ctx).pop(false)),
        DesignCompactButton(
          label: t.signUpOrLogin,
          color: DuelColors.green,
          width: 220,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder: (_) => const LoginScreen(popOnSuccess: true)),
  );
  if (ok == true && hasRegisteredAccount(ref)) {
    ref.read(lobbyProvider.notifier).refresh();
    return true;
  }
  return false;
}
