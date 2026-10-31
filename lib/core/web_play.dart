import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_theme.dart';
import 'duel_ui.dart';
import '../l10n/strings.dart';

/// HTTPS pages cannot use `ws://`; upgrade to `wss://` when possible.
String? normalizeWebSocketForWeb(String? url) {
  if (url == null || url.isEmpty) return url;
  if (!kIsWeb) return url;
  final page = Uri.base;
  if (page.scheme == 'https' && url.startsWith('ws://')) {
    return 'wss://${url.substring(5)}';
  }
  return url;
}

/// True when the browser is in portrait on a phone-sized web viewport.
bool webNeedsLandscapeRotate(BuildContext context) {
  if (!kIsWeb) return false;
  final mq = MediaQuery.of(context);
  final size = mq.size;
  if (size.height <= size.width * 1.02) return false;
  final phoneLike = size.shortestSide < 720 || size.width < 640;
  return phoneLike;
}

/// Full-screen gate for mobile web: play only in landscape.
class WebLandscapeGate extends ConsumerStatefulWidget {
  const WebLandscapeGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WebLandscapeGate> createState() => _WebLandscapeGateState();
}

class _WebLandscapeGateState extends ConsumerState<WebLandscapeGate> with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!webNeedsLandscapeRotate(context)) return widget.child;
    final t = ref.watch(stringsProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: widget.child),
        Positioned.fill(
          child: Material(
            color: const Color(0xF0070A18),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RotationTransition(
                        turns: Tween(begin: 0.0, end: 0.25).animate(CurvedAnimation(parent: _spin, curve: Curves.easeInOut)),
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: DuelColors.gold, width: 3),
                            boxShadow: [BoxShadow(color: DuelColors.gold.withValues(alpha: 0.35), blurRadius: 24)],
                          ),
                          child: const Icon(Icons.screen_rotation_rounded, size: 64, color: DuelColors.gold),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        t.webRotateTitle,
                        textAlign: TextAlign.center,
                        style: AppText.label(32, color: DuelColors.gold, weight: FontWeight.w900),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t.webRotateBody,
                        textAlign: TextAlign.center,
                        style: AppText.label(18, color: Colors.white, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t.webRotatePortraitLock,
                        textAlign: TextAlign.center,
                        style: AppText.label(15, color: DuelColors.dim, weight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Online match shell (landscape gate is app-wide via [WebLandscapeGate] on web).
class WebPlayScope extends ConsumerWidget {
  const WebPlayScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => child;
}
