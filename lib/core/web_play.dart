import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_theme.dart';
import 'duel_ui.dart';
import 'web_fullscreen.dart';
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

bool _phoneLikeViewport(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.shortestSide < 720 || size.width < 640;
}

bool _landscapeViewport(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width >= size.height * 0.98;
}

/// Mobile web: landscape-only play (1600×900 canvas); portrait shows rotate gate.
class WebLandscapeGate extends ConsumerStatefulWidget {
  const WebLandscapeGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WebLandscapeGate> createState() => _WebLandscapeGateState();
}

class _WebLandscapeGateState extends ConsumerState<WebLandscapeGate> with WidgetsBindingObserver {
  bool _fullscreenHintDismissed = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (kIsWeb) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!kIsWeb || !mounted) return;
    final ctx = context;
    if (!_phoneLikeViewport(ctx)) return;
    if (_landscapeViewport(ctx)) {
      webTryHideMobileBrowserChrome();
      setState(() {});
    }
  }

  Future<void> _onUserGestureForFullscreen() async {
    if (!kIsWeb) return;
    await webTryHideMobileBrowserChrome();
    if (webIsDomFullscreen() && mounted) {
      setState(() => _fullscreenHintDismissed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;

    final landscape = _landscapeViewport(context);
    final t = ref.watch(stringsProvider);

    if (!landscape) {
      return ColoredBox(
        color: DuelColors.ink,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.screen_rotation_rounded, color: DuelColors.gold, size: 56),
                  const SizedBox(height: 20),
                  Text(
                    t.webPlayLandscapeHint,
                    textAlign: TextAlign.center,
                    style: AppText.label(18, color: Colors.white, weight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.webPortraitPlayHint,
                    textAlign: TextAlign.center,
                    style: AppText.label(14, color: DuelColors.silver, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final phone = _phoneLikeViewport(context);
    final inFullscreen = webIsDomFullscreen();

    Widget content = widget.child;

    if (phone) {
      content = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!inFullscreen && !_fullscreenHintDismissed) {
            _onUserGestureForFullscreen();
          }
        },
        child: content,
      );
    }

    if (!phone) return content;

    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (landscape && !inFullscreen && !_fullscreenHintDismissed)
          Positioned(
            left: 16,
            right: 16,
            bottom: 8,
            child: SafeArea(
              top: false,
              child: GestureDetector(
                onTap: _onUserGestureForFullscreen,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: duelPanel(radius: 12, rim: DuelColors.gold),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.fullscreen_rounded, color: DuelColors.gold, size: 22),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          t.webFullscreenTap,
                          textAlign: TextAlign.center,
                          style: AppText.label(13, color: Colors.white, weight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.close_rounded, color: DuelColors.dim, size: 18),
                        onPressed: () => setState(() => _fullscreenHintDismissed = true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Online match shell (mobile web chrome via [WebLandscapeGate] on web).
class WebPlayScope extends ConsumerWidget {
  const WebPlayScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => child;
}
