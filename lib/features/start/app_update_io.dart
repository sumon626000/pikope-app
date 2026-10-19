import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import '../../l10n/strings.dart';
import '../online/session.dart';

const _channel = MethodChannel('pikope/update');

int _skippedCode = 0;
bool _dialogOpen = false;

/// Asks the server if a newer APK is published, then downloads it and opens
/// the Android installer. A phone cannot install silently; the system sheet
/// is the last step.
Future<void> checkForAppUpdate(BuildContext context, WidgetRef ref) async {
  if (!Platform.isAndroid || !Env.hasBackend || _dialogOpen) return;
  final api = ref.read(apiProvider);
  if (api == null) return;
  try {
    final remote = await api.get('/app/update');
    final code = _asInt(remote['versionCode']);
    final url = (remote['apkUrl'] as String?)?.trim() ?? '';
    if (code < 1 || url.isEmpty || code == _skippedCode) return;
    final local = await _localVersionCode();
    if (local < 1 || code <= local) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    final apiHost = Uri.tryParse(Env.apiBaseUrl)?.host.toLowerCase() ?? '';
    if (apiHost.isNotEmpty && uri.host.toLowerCase() != apiHost) return;
    if (!context.mounted) return;
    _dialogOpen = true;
    final required = remote['required'] == true;
    final sha = (remote['apkSha256'] as String?)?.trim().toLowerCase() ?? '';
    await showDialog<void>(
      context: context,
      barrierDismissible: !required,
      builder: (_) => _UpdateDialog(
        versionCode: code,
        versionName: (remote['versionName'] as String?)?.trim() ?? '',
        url: uri,
        apkSha256: sha.length == 64 ? sha : '',
        notes: (remote['notes'] as String?)?.trim() ?? '',
        requiredUpdate: required,
      ),
    );
  } catch (_) {
    // Offline or an old server: keep playing.
  } finally {
    _dialogOpen = false;
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

class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.apkSha256,
    required this.notes,
    required this.requiredUpdate,
  });

  final int versionCode;
  final String versionName;
  final Uri url;
  final String apkSha256;
  final String notes;
  final bool requiredUpdate;

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  double? _progress;
  String? _file;
  String? _error;
  bool _allowInstall = false;
  bool _busy = false;
  bool _opened = false;

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
    });
    HttpClient? client;
    IOSink? sink;
    final partial = File('${Directory.systemTemp.path}/pikope-update-partial.apk');
    try {
      final cache = await _channel.invokeMethod<String>('cacheDir');
      if (cache == null || cache.isEmpty) throw StateError('no cache');
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final response = await client.getUrl(widget.url).then((r) => r.close());
      if (response.statusCode != 200) throw StateError('http ${response.statusCode}');
      final dest = File('$cache/pikope-update.apk');
      if (dest.existsSync()) dest.deleteSync();
      sink = dest.openWrite();
      var got = 0;
      final total = response.contentLength;
      await for (final chunk in response.timeout(const Duration(minutes: 8))) {
        if (!mounted) return;
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) setState(() => _progress = got / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (got < 100000) throw StateError('short file');
      final head = await dest.openRead(0, 2).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      if (head.length < 2 || head[0] != 0x50 || head[1] != 0x4B) throw StateError('not an apk');
      if (widget.apkSha256.isNotEmpty) {
        final got = await _channel.invokeMethod<String>('fileSha256', {'path': dest.path});
        if (got?.toLowerCase() != widget.apkSha256) throw StateError('hash mismatch');
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ref.read(stringsProvider).updateFailed;
        });
      }
    } finally {
      await sink?.close();
      client?.close(force: true);
      if (partial.existsSync()) partial.deleteSync();
    }
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
    final name = widget.versionName.isEmpty ? '${widget.versionCode}' : widget.versionName;
    final ready = _file != null;
    return PopScope(
      canPop: !widget.requiredUpdate,
      child: Dialog(
        backgroundColor: const Color(0xFF12182E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Color(0xFFD9B45A), width: 2)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ready ? t.updateReady : t.updateTitle, style: AppText.label(28, color: DuelColors.gold, weight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                widget.notes.isEmpty ? t.updateBody(name) : widget.notes,
                textAlign: TextAlign.center,
                style: AppText.label(16, color: Colors.white, weight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              if (_error != null)
                Text(_error!, textAlign: TextAlign.center, style: AppText.label(15, color: const Color(0xFFFF8A8A), weight: FontWeight.w800))
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!widget.requiredUpdate)
                    TextButton(
                      onPressed: () {
                        _skippedCode = widget.versionCode;
                        Navigator.of(context).pop();
                      },
                      child: Text(t.updateLater, style: AppText.label(16, color: DuelColors.silver, weight: FontWeight.w800)),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: DuelColors.gold, foregroundColor: const Color(0xFF1A1204)),
                    onPressed: _error != null ? _download : (ready ? _install : null),
                    child: Text(_error != null ? t.updateRetry : t.updateInstall, style: AppText.label(16, weight: FontWeight.w900)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
