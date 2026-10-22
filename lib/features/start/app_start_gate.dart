import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import 'app_update.dart';
import 'loading_screen.dart';
import 'login_screen.dart';

/// Saved account opens the lobby. A new install still starts on sign-up.
/// Mandatory APK update runs before login or the lobby.
class AppStartGate extends ConsumerStatefulWidget {
  const AppStartGate({super.key});

  @override
  ConsumerState<AppStartGate> createState() => _AppStartGateState();
}

class _AppStartGateState extends ConsumerState<AppStartGate> {
  bool? _signedIn;
  AppUpdateOffer? _updateOffer;
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    _runUpdateCheck();
  }

  Future<void> _runUpdateCheck() async {
    final offer = await peekAppUpdate(ref);
    if (!mounted) return;
    setState(() {
      _updateOffer = offer;
      _updateChecked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_updateChecked) {
      return Scaffold(
        backgroundColor: DuelColors.ink,
        body: const Center(child: CircularProgressIndicator(color: DuelColors.gold)),
      );
    }
    if (_updateOffer != null) {
      return MandatoryUpdateScreen(offer: _updateOffer!);
    }

    _signedIn ??= Env.hasBackend && ref.read(settingsProvider).authToken.isNotEmpty;
    if (_signedIn!) {
      return const LoadingScreen();
    }
    return const LoginScreen();
  }
}
