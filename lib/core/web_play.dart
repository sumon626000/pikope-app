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

/// Online match shell: landscape hint on narrow portrait browsers.
class WebPlayScope extends ConsumerWidget {
  const WebPlayScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsWeb) return child;
    final size = MediaQuery.sizeOf(context);
    final portrait = size.height > size.width * 1.05;
    if (!portrait) return child;
    final t = ref.watch(stringsProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Material(
            color: Colors.black87,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                t.webPlayLandscapeHint,
                textAlign: TextAlign.center,
                style: AppText.label(12, color: DuelColors.gold, weight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
