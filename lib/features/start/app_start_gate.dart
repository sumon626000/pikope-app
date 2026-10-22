import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/env.dart';
import 'app_update.dart';
import 'loading_screen.dart';
import 'login_screen.dart';

/// Saved account opens the lobby. A new install still starts on sign-up.
/// The choice is made once, so signing in does not swap this widget out
/// from under the login fields.
class AppStartGate extends ConsumerStatefulWidget {
  const AppStartGate({super.key});

  @override
  ConsumerState<AppStartGate> createState() => _AppStartGateState();
}

class _AppStartGateState extends ConsumerState<AppStartGate> {
  bool? _signedIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkForAppUpdate(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Lock route once so login fields are not replaced mid-typing on rebuild.
    _signedIn ??= Env.hasBackend && ref.read(settingsProvider).authToken.isNotEmpty;
    if (_signedIn!) {
      // Restore session and warm assets before the lobby.
      return const LoadingScreen();
    }
    return const LoginScreen();
  }
}
