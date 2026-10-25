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

/// In-shop tutorial: 16:9 frame with thumbnail; tap plays YouTube in-app.
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

  @override
  Widget build(BuildContext context) {
    final id = youtubeVideoId(youtubeUrl);
    if (id == null) return const SizedBox.shrink();
    final thumb = 'https://img.youtube.com/vi/$id/hqdefault.jpg';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.label(16, color: DuelColors.gold, weight: FontWeight.w900)),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Material(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CoinTutorialPlayerScreen(videoId: id, title: title),
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1A1A24)),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(color: DuelColors.gold, width: 2),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: DuelColors.gold, size: 44),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: Text(
                        tapHint,
                        textAlign: TextAlign.center,
                        style: AppText.label(12, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
      body: SafeArea(child: WebViewWidget(controller: _web)),
    );
  }
}
