import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../l10n/strings.dart';
import 'login_auth_panel.dart';
import 'start_route.dart';

/// Full-screen sign-in (tests / rare deep link). In-app gating uses [showLoginAuthPopup].
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.popOnSuccess = false});

  final bool popOnSuccess;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(audioProvider).playMenuMusic().catchError((_) {});
    });
  }

  void _onAuthenticated() {
    FocusManager.instance.primaryFocus?.unfocus();
    final navigator = Navigator.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted) return;
      if (widget.popOnSuccess) {
        navigator.pop(true);
        return;
      }
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => homeScreenFor()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return PortraitCanvas(
      minHeight: 1500,
      builder: (context, height) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 50, 40, 60),
        child: Column(
          children: [
            const DuelLogo(height: 240),
            const SizedBox(height: 20),
            Text(titleCase(s.taglineGames), textAlign: TextAlign.center, style: pcText(36, color: const Color(0xFFE6E2FF))),
            const SizedBox(height: 8),
            Text(s.taglinePick, textAlign: TextAlign.center, style: pcText(26, color: DesignColors.pcGold, weight: FontWeight.w500)),
            const SizedBox(height: 40),
            LoginAuthPanel(compact: false, onAuthenticated: _onAuthenticated),
          ],
        ),
      ),
    );
  }
}
