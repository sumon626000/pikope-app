import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/duel_ui.dart';
import 'app_update.dart';
import 'loading_screen.dart';
/// Fast loading splash, then home. Sign-in / sign-up when play or wallet needs an account.
/// Mandatory APK update runs before the lobby.
class AppStartGate extends ConsumerStatefulWidget {
  const AppStartGate({super.key});

  @override
  ConsumerState<AppStartGate> createState() => _AppStartGateState();
}

class _AppStartGateState extends ConsumerState<AppStartGate> {
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

    return const LoadingScreen();
  }
}
