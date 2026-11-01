import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/brand.dart';
import '../../core/design/design.dart';
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import '../duel/duel_home_screen.dart';
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
  static const _minimum = Duration(milliseconds: 650);
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
      final work = Future.wait<void>([
        for (final image in images)
          precacheImage(image, context).catchError((_) {}),
      ]);
      unawaited(
        audio.warmUp().then((_) => audio.playMenuMusic()).catchError((_) {}),
      );
      // Finish session restore before home so Shop/wallet do not flash login.
      await Future.wait<void>([
        work,
        _restoreRegisteredSession(),
        Future<void>.delayed(_minimum),
      ]);
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

  Future<void> _restoreRegisteredSession() async {
    if (!Env.hasBackend) return;
    try {
      final ok = await ref
          .read(sessionProvider.notifier)
          .tryRestoreExistingSession()
          .timeout(const Duration(seconds: 8));
      if (ok) {
        ref
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(onboarded: true));
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
      child: LoadingSplashBody(
        message: s.loadingBilliard,
        progress: AnimatedBuilder(
          animation: _bar,
          builder: (_, _) => ClipRRect(
            borderRadius: BorderRadius.circular(DesignRadii.sm),
            child: LinearProgressIndicator(
              value: Curves.easeInOut.transform(_bar.value),
              minHeight: 12,
              backgroundColor: const Color(0xFF2B2B38),
              valueColor: const AlwaysStoppedAnimation(AppColors.active),
            ),
          ),
        ),
      ),
    );
  }
}

/// Static splash layout (also used in Phase 7 responsive tests).
class LoadingSplashBody extends StatelessWidget {
  const LoadingSplashBody({
    super.key,
    required this.message,
    required this.progress,
  });

  final String message;
  final Widget progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DuelLogo(height: 168),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                _LoadingGameCard(
                  rim: DesignColors.poolEightAccent,
                  label: 'POOL',
                  art: BilliardArt(),
                ),
                SizedBox(width: DesignSpacing.x5),
                _LoadingGameCard(
                  rim: DesignColors.ludoAccent,
                  label: 'LUDO',
                  art: LudoArt(),
                ),
                SizedBox(width: DesignSpacing.x5),
                _LoadingGameCard(
                  rim: DesignColors.carromAccent,
                  label: 'CARROM',
                  art: CarromArt(),
                ),
              ],
            ),
            const SizedBox(height: DesignSpacing.x6),
            Text(
              message,
              style: AppText.label(
                22,
                color: DuelColors.silver,
                weight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: DesignSpacing.x8),
            SizedBox(width: 480, child: progress),
          ],
        ),
      ),
    );
  }
}

class _LoadingGameCard extends StatelessWidget {
  const _LoadingGameCard({
    required this.rim,
    required this.label,
    required this.art,
  });

  final Color rim;
  final String label;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 168,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: rim.withValues(alpha: 0.55), width: 2),
        boxShadow: [
          BoxShadow(
            color: rim.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            art,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                color: Colors.black.withValues(alpha: 0.35),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppText.label(
                    14,
                    color: Colors.white,
                    weight: FontWeight.w900,
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
