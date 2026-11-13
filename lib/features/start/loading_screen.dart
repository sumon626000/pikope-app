import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/brand.dart';
import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
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
    // Cold start / F5: same account token in storage → auto rejoin seated match.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(resumeActiveOnlineMatch(ref));
    });
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
    return PortraitCanvas(
      minHeight: 1400,
      builder: (context, height) => LoadingSplashBody(
        message: s.loadingBilliard,
        progress: AnimatedBuilder(
          animation: _bar,
          builder: (_, _) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: Curves.easeInOut.transform(_bar.value),
              minHeight: 22,
              backgroundColor: const Color(0xFF2A1C5E),
              valueColor: const AlwaysStoppedAnimation(DesignColors.pcGold),
            ),
          ),
        ),
      ),
    );
  }
}

/// Splash layout in 1080-wide design units (also used in the responsive
/// tests): logo, the three game cards, a message and the progress bar.
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
    // Compact phone-style splash: logo + 3 small cards in one row + bar.
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: SizedBox(
          width: PortraitCanvas.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DuelLogo(height: 200),
              const SizedBox(height: 36),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LoadingGameCard(
                    rim: DesignColors.pcTileOrange,
                    label: 'POOL',
                    art: BilliardArt(),
                  ),
                  SizedBox(width: 16),
                  _LoadingGameCard(
                    rim: DesignColors.pcTilePink,
                    label: 'LUDO',
                    art: LudoArt(),
                  ),
                  SizedBox(width: 16),
                  _LoadingGameCard(
                    rim: DesignColors.pcTileTeal,
                    label: 'CARROM',
                    art: CarromArt(),
                  ),
                ],
              ),
              const SizedBox(height: 44),
              Text(
                titleCase(message),
                style: pcText(32, color: const Color(0xFFE6E2FF)),
              ),
              const SizedBox(height: 28),
              SizedBox(width: 560, child: progress),
            ],
          ),
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

  static const width = 220.0;
  static const height = 138.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: rim.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          const BoxShadow(
            color: Color(0x99000000),
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
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
                color: Colors.black.withValues(alpha: 0.4),
                child: Text(
                  titleCase(label),
                  textAlign: TextAlign.center,
                  style: pcText(26),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
