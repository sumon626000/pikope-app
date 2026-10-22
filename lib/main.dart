import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/app_state.dart';
import 'core/app_theme.dart';
import 'core/brand.dart';
import 'core/perf.dart';
import 'data/app_storage.dart';
import 'core/push_service.dart';
import 'features/duel/challenge_inbox_host.dart';
import 'features/start/app_start_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) => Material(
        color: const Color(0xFF070A18),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              kReleaseMode ? 'Something went wrong. Please restart the app.' : details.exceptionAsString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE9ECF5),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      );
  try {
    await PushService.initLocal();
  } catch (_) {
    // Notifications optional — must not block launch.
  }
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  if (const bool.fromEnvironment('PERF_LOG')) _logFrameTimings();
  AppStorage storage;
  try {
    storage = await PrefsStorage.open();
  } catch (_) {
    storage = MemoryStorage();
  }
  runApp(ProviderScope(
    overrides: [storageProvider.overrideWithValue(storage)],
    child: const BilliardPokerApp(),
  ));
}

class BilliardPokerApp extends ConsumerWidget {
  const BilliardPokerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(settingsProvider.select((s) => s.languageCode));
    return MaterialApp(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: Locale(lang == 'bn' ? 'bn' : 'en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppStartGate(),
      builder: (context, child) => ChallengeInboxHost(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Build with `--dart-define=PERF_LOG=true` to print frame statistics every
/// 300 frames (build = Dart UI thread, raster = GPU thread).
void _logFrameTimings() {
  final frames = <FrameTiming>[];
  SchedulerBinding.instance.addTimingsCallback((timings) {
    frames.addAll(timings);
    if (frames.length < 300) return;
    double ms(Duration d) => d.inMicroseconds / 1000;
    String stats(List<double> v) {
      v.sort();
      final avg = v.reduce((a, b) => a + b) / v.length;
      return 'avg ${avg.toStringAsFixed(1)} p90 ${v[(v.length * 0.9).floor()].toStringAsFixed(1)} '
          'p99 ${v[(v.length * 0.99).floor()].toStringAsFixed(1)} max ${v.last.toStringAsFixed(1)}';
    }

    // A frame is late when either thread alone misses the 60 Hz budget.
    final slow = frames
        .where((f) => ms(f.buildDuration) > 16.7 || ms(f.rasterDuration) > 16.7)
        .length;
    debugPrint('PERF frames ${frames.length} | build ${stats([for (final f in frames) ms(f.buildDuration)])}'
        ' | raster ${stats([for (final f in frames) ms(f.rasterDuration)])} | late: $slow'
        ' | ${Perf.report()}');
    frames.clear();
  });
}
