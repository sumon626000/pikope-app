import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/brand.dart';
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import '../online/online_screens.dart';
import '../online/session.dart';
import 'start_route.dart';
import '../../l10n/strings.dart';

/// Returning players: quick splash while session restores, then home.
class LoadingScreen extends ConsumerStatefulWidget {
  const LoadingScreen({super.key});

  @override
  ConsumerState<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends ConsumerState<LoadingScreen>
    with SingleTickerProviderStateMixin {
  static const _minimum = Duration(milliseconds: 350);
  late final AnimationController _bar = AnimationController(
    vsync: this,
    duration: _minimum,
  )..forward();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final images = [
        const AssetImage('assets/images/pikope_logo.png'),
        const AssetImage(PicoCoin.asset),
      ];
      final audio = ref.read(audioProvider);
      unawaited(_restoreSavedSession());
      final work = Future.wait<void>([
        for (final image in images)
          precacheImage(image, context).catchError((_) {}),
      ]);
      unawaited(audio.warmUp().then((_) => audio.playMenuMusic()).catchError((_) {}));
      await Future.wait<void>([work, Future<void>.delayed(_minimum)]);
    } catch (_) {
      // Still open home — a saved login restores in background.
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => homeScreenFor(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
    // Browser F5: same account token in storage → auto rejoin seated match.
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(resumeActiveOnlineMatch(ref));
      });
    }
  }

  Future<void> _restoreSavedSession() async {
    if (!Env.hasBackend) return;
    try {
      final ok = await ref.read(sessionProvider.notifier).tryRestoreExistingSession().timeout(const Duration(seconds: 8));
      if (ok) {
        ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboarded: true));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return DuelCanvas(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const DuelLogo(height: 200),
          const SizedBox(height: 20),
          Text(
            s.loadingBilliard,
            style: AppText.label(
              22,
              color: DuelColors.silver,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: 480,
            child: AnimatedBuilder(
              animation: _bar,
              builder: (_, _) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: Curves.easeInOut.transform(_bar.value),
                  minHeight: 12,
                  backgroundColor: const Color(0xFF2B2B38),
                  valueColor: const AlwaysStoppedAnimation(AppColors.active),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
