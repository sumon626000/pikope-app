import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'web_fullscreen.dart';

/// Screen orientation a route wants. The app default is portrait (home and
/// every Pool City page); the pool tables and the remaining 1600×900
/// landscape canvases opt in with [OrientationLock].
enum AppOrientation { landscape, portrait }

/// Watches page routes so [OrientationLock] hears pushes and pops. Registered
/// on the root [Navigator] in `app_bootstrap.dart`. Dialogs are popup routes,
/// not page routes, so opening one never changes the orientation.
final routeObserver = RouteObserver<PageRoute<dynamic>>();

/// Applies orientations and remembers the last request, so a route that
/// hands over to another portrait route does not flip through landscape.
abstract final class AppOrientationController {
  /// Portrait, like the reference app; the pool tables (and any page still
  /// on the 1600×900 canvas) lock landscape while they are on top.
  static const defaultOrientation = AppOrientation.portrait;

  static AppOrientation _desired = defaultOrientation;

  /// What the top route asked for (or the default). Web's landscape gate
  /// listens to this so portrait screens are not blocked by the rotate hint.
  static final ValueNotifier<AppOrientation> current = ValueNotifier(defaultOrientation);

  static void request(AppOrientation orientation) {
    _desired = orientation;
    _apply(orientation);
  }

  /// Back to the default — unless another screen claims an orientation in
  /// the same frame (a portrait route pushed on top of a portrait route).
  static void release() {
    _desired = defaultOrientation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_desired == defaultOrientation) _apply(defaultOrientation);
    });
  }

  static Future<void> _apply(AppOrientation orientation) async {
    if (current.value != orientation) current.value = orientation;
    if (kIsWeb) {
      await webTryLockOrientation(orientation == AppOrientation.portrait ? 'portrait' : 'landscape');
      return;
    }
    await SystemChrome.setPreferredOrientations(
      orientation == AppOrientation.portrait
          ? const [DeviceOrientation.portraitUp]
          : const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
  }
}

/// Keeps the device in [orientation] while the enclosing page route is on
/// top of the stack; restores the app default when another route covers it
/// or when it is popped. Put it directly under the screen's `Scaffold`.
class OrientationLock extends StatefulWidget {
  const OrientationLock({super.key, required this.orientation, required this.child});

  final AppOrientation orientation;
  final Widget child;

  @override
  State<OrientationLock> createState() => _OrientationLockState();
}

class _OrientationLockState extends State<OrientationLock> with RouteAware {
  PageRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      if (route == _route) return;
      if (_route != null) routeObserver.unsubscribe(this);
      _route = route;
      // subscribe() calls didPush() straight away for the current route.
      routeObserver.subscribe(this, route);
    } else if (_route == null) {
      // Not inside a page route (widget tests): just ask once.
      AppOrientationController.request(widget.orientation);
    }
  }

  @override
  void didUpdateWidget(OrientationLock old) {
    super.didUpdateWidget(old);
    if (old.orientation != widget.orientation && (_route?.isCurrent ?? true)) {
      AppOrientationController.request(widget.orientation);
    }
  }

  @override
  void dispose() {
    if (_route != null) routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() => AppOrientationController.request(widget.orientation);

  @override
  void didPopNext() => AppOrientationController.request(widget.orientation);

  @override
  void didPushNext() => AppOrientationController.release();

  @override
  void didPop() => AppOrientationController.release();

  @override
  Widget build(BuildContext context) => widget.child;
}
