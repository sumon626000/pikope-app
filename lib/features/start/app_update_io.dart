import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import '../../l10n/strings.dart';
import '../online/session.dart';

const _channel = MethodChannel('pikope/update');

/// Server says a newer APK exists; user must install before using the app.
class AppUpdateOffer {
  const AppUpdateOffer({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.apkSha256,
    required this.notes,
  });

  final int versionCode;
  final String versionName;
  final Uri url;
  final String apkSha256;
  final String notes;
}

bool _dialogOpen = false;

/// Returns an offer when the installed build is older than the published one.
Future<AppUpdateOffer?> peekAppUpdate(WidgetRef ref) async {
  if (!Platform.isAndroid || !Env.hasBackend) return null;
  final api = ref.read(apiProvider);
  if (api == null) return null;
  try {
    final remote = await api.get('/app/update');
    final code = _asInt(remote['versionCode']);
    final url = (remote['apkUrl'] as String?)?.trim() ?? '';
    if (code < 1 || url.isEmpty) return null;
    final local = await _localVersionCode();
    if (local < 1 || code <= local) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    final sha = (remote['apkSha256'] as String?)?.trim().toLowerCase() ?? '';
    return AppUpdateOffer(
      versionCode: code,
      versionName: (remote['versionName'] as String?)?.trim() ?? '',
      url: uri,
      apkSha256: sha.length == 64 ? sha : '',
      notes: (remote['notes'] as String?)?.trim() ?? '',
    );
  } catch (_) {
    return null;
  }
}

@Deprecated('Use peekAppUpdate + MandatoryUpdateScreen from AppStartGate')
Future<void> checkForAppUpdate(BuildContext context, WidgetRef ref) async {
  if (!Platform.isAndroid || !Env.hasBackend || _dialogOpen) return;
  final offer = await peekAppUpdate(ref);
  if (offer == null || !context.mounted) return;
  _dialogOpen = true;
  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MandatoryUpdateScreen(offer: offer),
      ),
    );
  } finally {
    _dialogOpen = false;
  }
}

/// Blocks the whole app until the update is downloaded and the installer opens.
class MandatoryUpdateScreen extends ConsumerStatefulWidget {
  const MandatoryUpdateScreen({super.key, required this.offer});

  final AppUpdateOffer offer;

  @override
  ConsumerState<MandatoryUpdateScreen> createState() => _MandatoryUpdateScreenState();
}

class _MandatoryUpdateScreenState extends ConsumerState<MandatoryUpdateScreen> {
  double? _progress;
  String? _file;
  String? _error;
  bool _allowInstall = false;
  bool _busy = false;
  bool _opened = false;

  AppUpdateOffer get offer => widget.offer;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
      _file = null;
      _allowInstall = false;
      _opened = false;
    });
    http.Client? client;
    IOSink? sink;
    try {
      final cache = await _channel.invokeMethod<String>('cacheDir');
      if (cache == null || cache.isEmpty) throw StateError('cache');
      client = http.Client();
      final request = http.Request('GET', offer.url);
      request.headers['User-Agent'] = 'PikoPe-Android';
      request.headers['Accept'] = 'application/vnd.android.package-archive,*/*';
      final response = await client.send(request).timeout(const Duration(minutes: 10));
      if (response.statusCode != 200) throw StateError('http_${response.statusCode}');
      final dest = File('$cache/pikope-update.apk');
      if (dest.existsSync()) dest.deleteSync();
      sink = dest.openWrite();
      var got = 0;
      final total = response.contentLength;
      await for (final chunk in response.stream.timeout(const Duration(minutes: 10))) {
        if (!mounted) return;
        sink.add(chunk);
        got += chunk.length;
        if (total != null && total > 0) setState(() => _progress = got / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (got < 100000) throw StateError('short');
      final head = await dest.openRead(0, 2).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      if (head.length < 2 || head[0] != 0x50 || head[1] != 0x4B) throw StateError('not_apk');
      if (offer.apkSha256.isNotEmpty) {
        final hash = await _channel.invokeMethod<String>('fileSha256', {'path': dest.path});
        if (hash?.toLowerCase() != offer.apkSha256) throw StateError('hash');
      }
      if (!mounted) return;
      setState(() {
        _file = dest.path;
        _progress = 1;
        _busy = false;
      });
      if (!_opened) {
        _opened = true;
        await _install();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _downloadErrorMessage(ref.read(stringsProvider), e);
        });
      }
    } finally {
      await sink?.close();
      client?.close();
    }
  }

  String _downloadErrorMessage(AppStrings t, Object e) {
    final code = e is StateError ? e.message : '';
    if (code.startsWith('http_404')) {
      return '${t.updateFailed}\n${t.updateFailed404}';
    }
    if (code.startsWith('http_')) {
      return '${t.updateFailed}\n${t.updateFailedHttp(code.replaceFirst('http_', ''))}';
    }
    if (code == 'hash') return '${t.updateFailed}\n${t.updateFailedHash}';
    if (code == 'not_apk') return '${t.updateFailed}\n${t.updateFailedNotApk}';
    return t.updateFailed;
  }

  Future<void> _install() async {
    final path = _file;
    if (path == null) return;
    try {
      final ok = await _channel.invokeMethod<bool>('install', {'path': path}) ?? false;
      if (!mounted) return;
      setState(() => _allowInstall = !ok);
    } catch (_) {
      if (mounted) setState(() => _allowInstall = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final name = offer.versionName.isEmpty ? '${offer.versionCode}' : offer.versionName;
    final ready = _file != null;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: DuelColors.ink,
        body: DuelBackdrop(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(ready ? t.updateReady : t.updateTitle, style: AppText.label(28, color: DuelColors.gold, weight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      Text(
                        offer.notes.isEmpty ? t.updateBody(name) : offer.notes,
                        textAlign: TextAlign.center,
                        style: AppText.label(16, color: Colors.white, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(t.updateRequiredHint, textAlign: TextAlign.center, style: AppText.label(13, color: DuelColors.silver, weight: FontWeight.w600)),
                      const SizedBox(height: 18),
                      if (_error != null)
                        Text(_error!, textAlign: TextAlign.center, style: AppText.label(14, color: const Color(0xFFFF8A8A), weight: FontWeight.w800))
                      else
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 12,
                            backgroundColor: const Color(0xFF2B2B38),
                            color: DuelColors.gold,
                          ),
                        ),
                      if (_allowInstall) ...[
                        const SizedBox(height: 12),
                        Text(t.updateAllow, textAlign: TextAlign.center, style: AppText.label(14, color: DuelColors.silver, weight: FontWeight.w700)),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: DuelColors.gold, foregroundColor: const Color(0xFF1A1204), minimumSize: const Size(200, 48)),
                        onPressed: _error != null ? _download : (ready ? _install : null),
                        child: Text(_error != null ? t.updateRetry : t.updateInstall, style: AppText.label(16, weight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

Future<int> _localVersionCode() async {
  try {
    final value = await _channel.invokeMethod<Object>('versionCode');
    return _asInt(value);
  } catch (_) {
    return 0;
  }
}
