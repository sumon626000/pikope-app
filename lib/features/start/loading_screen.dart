import 'dart:async';

import 'package:flutter/foundation.dart';
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
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: SizedBox(
          width: PortraitCanvas.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DuelLogo(height: 300),
              const SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  _LoadingGameCard(
                    rim: DesignColors.pcTileOrange,
                    label: 'POOL',
                    art: BilliardArt(),
                  ),
                  SizedBox(width: 24),
                  _LoadingGameCard(
                    rim: DesignColors.pcTilePink,
                    label: 'LUDO',
                    art: LudoArt(),
                  ),
                  SizedBox(width: 24),
                  _LoadingGameCard(
                    rim: DesignColors.pcTileTeal,
                    label: 'CARROM',
                    art: CarromArt(),
                  ),
                ],
              ),
              const SizedBox(height: 70),
              Text(titleCase(message), style: pcText(36, color: const Color(0xFFE6E2FF))),
              const SizedBox(height: 40),
              SizedBox(width: 700, child: progress),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 3),
        boxShadow: [
          BoxShadow(color: rim.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8)),
          const BoxShadow(color: Color(0x99000000), blurRadius: 14, offset: Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: [
            art,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: Colors.black.withValues(alpha: 0.4),
                child: Text(titleCase(label), textAlign: TextAlign.center, style: pcText(34)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
