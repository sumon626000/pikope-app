import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import 'app_update.dart';
import 'login_screen.dart';
import 'start_route.dart';

/// Saved account opens the lobby. A new install still starts on sign-up.
/// The choice is made once, so signing in does not swap this widget out
/// from under the login fields.
class AppStartGate extends ConsumerStatefulWidget {
  const AppStartGate({super.key});

  @override
  ConsumerState<AppStartGate> createState() => _AppStartGateState();
}

class _AppStartGateState extends ConsumerState<AppStartGate> {
  late final bool _signedIn;

  @override
  void initState() {
    super.initState();
    _signedIn = ref.read(settingsProvider).authToken.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkForAppUpdate(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => _signedIn ? homeScreenFor() : const LoginScreen();
}
