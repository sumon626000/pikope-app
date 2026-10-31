import 'package:billiard_poker/app_bootstrap.dart';

/// Web entry — no immersive Android chrome; same app tree as APK.
Future<void> main() => bootstrapPikope(mobileShell: false);
