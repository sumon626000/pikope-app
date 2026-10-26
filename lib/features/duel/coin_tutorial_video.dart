import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';

/// Parses watch / youtu.be / embed URLs.
String? youtubeVideoId(String url) {
  final raw = url.trim();
  if (raw.isEmpty) return null;
  final u = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
  if (u == null) return null;
  if (u.host.contains('youtu.be') && u.pathSegments.isNotEmpty) {
    return u.pathSegments.first.split('?').first;
  }
  if (u.host.contains('youtube.com')) {
    final v = u.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    for (final seg in u.pathSegments) {
      if (seg == 'embed' || seg == 'shorts') {
        final i = u.pathSegments.indexOf(seg);
        if (i + 1 < u.pathSegments.length) return u.pathSegments[i + 1];
      }
    }
  }
  return null;
}

String youtubeEmbedUrl(String videoId, {bool autoplay = false}) =>
    'https://www.youtube.com/embed/$videoId?playsinline=1&rel=0&modestbranding=1${autoplay ? '&autoplay=1' : ''}';

/// Compact in-shop tutorial strip: small thumbnail + title, not a full 16:9 player.
class CoinTutorialVideoFrame extends StatelessWidget {
  const CoinTutorialVideoFrame({
    super.key,
    required this.youtubeUrl,
    required this.title,
    required this.tapHint,
  });

  final String youtubeUrl;
  final String title;
  final String tapHint;

  static const _thumbW = 118.0;
  static const _h = 68.0;

  @override
  Widget build(BuildContext context) {
    final id = youtubeVideoId(youtubeUrl);
    if (id == null) return const SizedBox.shrink();
    final thumb = 'https://img.youtube.com/vi/$id/mqdefault.jpg';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF0A1228),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CoinTutorialPlayerScreen(videoId: id, title: title),
            ),
          ),
          child: Container(
            height: _h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DuelColors.gold.withValues(alpha: 0.42)),
              boxShadow: [
                BoxShadow(color: DuelColors.gold.withValues(alpha: 0.12), blurRadius: 10),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: _thumbW,
                  height: _h,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF141A2E)),
                      ),
                      const ColoredBox(color: Color(0x66000000)),
                      Center(
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                            border: Border.all(color: DuelColors.gold, width: 1.6),
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: DuelColors.gold, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(13, color: DuelColors.gold, weight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tapHint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(11, color: DuelColors.silver),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(Icons.play_circle_outline_rounded, color: DuelColors.gold, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CoinTutorialPlayerScreen extends StatefulWidget {
  const CoinTutorialPlayerScreen({super.key, required this.videoId, required this.title});

  final String videoId;
  final String title;

  @override
  State<CoinTutorialPlayerScreen> createState() => _CoinTutorialPlayerScreenState();
}

class _CoinTutorialPlayerScreenState extends State<CoinTutorialPlayerScreen> {
  late final WebViewController _web;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadRequest(Uri.parse(youtubeEmbedUrl(widget.videoId, autoplay: true)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121A),
        foregroundColor: Colors.white,
        title: Text(widget.title, style: AppText.label(16, weight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: WebViewWidget(controller: _web),
            ),
          ),
        ),
      ),
    );
  }
}
