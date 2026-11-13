import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool webIsDomFullscreen() => web.document.fullscreenElement != null;

Future<void> webTryEnterFullscreen() async {
  if (webIsDomFullscreen()) return;
  final el = web.document.documentElement;
  if (el == null) return;
  try {
    await el.requestFullscreen().toDart;
  } catch (_) {
    // Needs a user gesture on many mobile browsers.
  }
}

Future<void> webTryHideMobileBrowserChrome() async {
  await webTryEnterFullscreen();
  try {
    web.window.scrollTo(web.ScrollToOptions(left: 0, top: 1));
  } catch (_) {}
}

/// Best-effort; may require a user gesture on some mobile browsers.
Future<void> webTryLockLandscape() => webTryLockOrientation('landscape');

/// [type] is a Screen Orientation API lock type: 'landscape' or 'portrait'.
Future<void> webTryLockOrientation(String type) async {
  try {
    await web.window.screen.orientation.lock(type).toDart;
  } catch (_) {}
}
