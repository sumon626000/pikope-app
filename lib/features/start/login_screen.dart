import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/design/design.dart';
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
    if (DesignBreakpoints.portraitLayout(context)) {
      return DuelCanvas(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            const Center(child: DuelLogo(height: 72)),
            const SizedBox(height: 12),
            Text(
              s.taglineGames,
              textAlign: TextAlign.center,
              style: AppText.label(
                16,
                color: DuelColors.silver,
                weight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.taglinePick,
              textAlign: TextAlign.center,
              style: AppText.label(13, color: AppColors.gold),
            ),
            const SizedBox(height: 16),
            LoginAuthPanel(compact: true, onAuthenticated: _onAuthenticated),
          ],
        ),
      );
    }
    return DuelCanvas(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignSpacing.x10,
          DesignSpacing.x4,
          DesignSpacing.x6,
          DesignSpacing.x4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 5,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: DesignSpacing.x10,
                    right: DesignSpacing.x8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DuelLogo(height: 190),
                      const SizedBox(height: DesignSpacing.x6),
                      Text(
                        s.taglineGames,
                        style: AppText.label(
                          24,
                          color: DuelColors.silver,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.taglinePick,
                        style: AppText.label(16, color: AppColors.gold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 7,
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: DesignAuth.loginFormMaxWidth,
                    ),
                    child: LoginAuthPanel(
                      compact: false,
                      onAuthenticated: _onAuthenticated,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
