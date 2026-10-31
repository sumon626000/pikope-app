import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'duel_ui.dart';
import 'env.dart';
import 'web_apk_platform.dart';
import '../data/api_client.dart';
import '../l10n/strings.dart';

/// Optional bottom chip on mobile web (Android browser): download the APK.
/// Hidden when the app runs installed (PWA standalone) or user chose “already installed”.
class WebApkPromoHost extends ConsumerStatefulWidget {
  const WebApkPromoHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WebApkPromoHost> createState() => _WebApkPromoHostState();
}

class _WebApkPromoHostState extends ConsumerState<WebApkPromoHost> {
  String? _apkUrl;
  bool _loading = true;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _loadApkUrl();
  }

  Future<void> _loadApkUrl() async {
    if (!Env.hasBackend) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final api = ApiClient(Env.apiBaseUrl);
      final j = await api.get('/landing/public');
      api.close();
      final url = (j['apkUrl'] as String?)?.trim() ?? '';
      if (mounted) {
        setState(() {
          _apkUrl = url.isNotEmpty ? url : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _showPromo {
    if (!kIsWeb || _loading || _hidden || _apkUrl == null) return false;
    if (!webApkPromoPlatformEligible()) return false;
    if (webApkPromoUserHasInstalledApp()) return false;
    return true;
  }

  Future<void> _download() async {
    final url = _apkUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _dismissInstalled() {
    webApkPromoMarkHasInstalledApp();
    setState(() => _hidden = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_showPromo) return widget.child;
    final t = ref.watch(stringsProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: duelPanel(radius: 14, rim: DuelColors.green, glow: true),
                child: Row(
                  children: [
                    const Icon(Icons.android_rounded, color: DuelColors.green, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.webApkPromoTitle, style: AppText.label(14, weight: FontWeight.w900)),
                          Text(t.webApkPromoHint, style: AppText.label(11, color: DuelColors.dim)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _dismissInstalled,
                      child: Text(t.webApkPromoHaveApp, style: AppText.label(11, color: DuelColors.silver)),
                    ),
                    const SizedBox(width: 4),
                    DuelButton(
                      label: t.webApkPromoDownload,
                      width: 120,
                      height: 40,
                      fontSize: 13,
                      color: DuelColors.green,
                      onPressed: _download,
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
