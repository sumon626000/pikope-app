import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
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
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(22),
        decoration: duelPanel(rim: DuelColors.gold),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.login_rounded, color: DuelColors.gold, size: 40),
            const SizedBox(height: 10),
            Text(t.loginRequiredTitle, textAlign: TextAlign.center, style: AppText.label(18, weight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text(
              t.loginRequiredBody,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'sans-serif', fontSize: 14, height: 1.4, color: DuelColors.silver),
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
                  label: t.signIn,
                  width: 160,
                  height: 42,
                  fontSize: 15,
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
  if (go != true || !context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder: (_) => const LoginScreen(popOnSuccess: true)),
  );
  return ok == true && hasRegisteredAccount(ref);
}
