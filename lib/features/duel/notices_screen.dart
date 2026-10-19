import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../data/api_client.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import '../../l10n/strings.dart';

/// The inbox: operator announcements (news) and banners.
class NoticesScreen extends ConsumerStatefulWidget {
  const NoticesScreen({super.key});

  @override
  ConsumerState<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends ConsumerState<NoticesScreen> {
  late final Future<List<Map<String, dynamic>>> _notices = ref.read(sessionProvider.notifier).notices();

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return DuelPage(
      title: t.noticesTitle,
      sub: t.noticesSub,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _notices,
        builder: (context, snap) {
          if (snap.hasError) {
            final offline = snap.error is ApiException;
            return Center(
              child: Text(
                offline ? t.offlineServer : t.noticesLoadFail,
                style: AppText.label(18, color: DuelColors.red),
              ),
            );
          }
          final notices = snap.data;
          if (notices == null) {
            return const Center(child: CircularProgressIndicator(color: DuelColors.silver));
          }
          if (notices.isEmpty) {
            return Center(child: Text(t.noticesEmpty, style: AppText.label(20, color: DuelColors.dim)));
          }
          return ListView.separated(
            itemCount: notices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _NoticeCard(notice: notices[i]),
          );
        },
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});

  final Map<String, dynamic> notice;

  @override
  Widget build(BuildContext context) {
    final banner = notice['kind'] == 'banner';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: duelPanel(radius: 14, rim: banner ? DuelColors.gold : DuelColors.rim),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(banner ? Icons.campaign_rounded : Icons.mail_rounded,
                  color: banner ? DuelColors.gold : DuelColors.silver, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  (notice['title'] as String).toUpperCase(),
                  style: AppText.label(18, color: banner ? DuelColors.gold : DuelColors.silver, weight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            notice['body'] as String,
            style: const TextStyle(fontFamily: 'sans-serif', fontSize: 14, height: 1.4, color: DuelColors.silver),
          ),
        ],
      ),
    );
  }
}
