import 'package:web/web.dart' as web;

void stripZiniPayQueryFromBrowserUrl() {
  final path = web.window.location.pathname;
  web.window.history.replaceState(null, '', path.isEmpty ? '/' : path);
}
