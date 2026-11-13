import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../data/api_client.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import '../../l10n/strings.dart';

/// The inbox: operator announcements (news) and banners. Opens as the
/// reference's "Mail" dialog from home; [NoticesScreen] is the same list as
/// a page for other callers.
Future<void> showNoticesDialog(BuildContext context, WidgetRef ref) {
  final t = ref.read(stringsProvider);
  final notices = ref.read(sessionProvider.notifier).notices();
  return showDuelDialog<void>(
    context,
    builder: (dialog) => PcDialog(
      title: t.noticesTitle,
      scroll: false,
      maxBodyHeight: 1500,
      child: SizedBox(height: 1300, child: NoticesList(notices: notices)),
    ),
  );
}

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
      child: NoticesList(notices: _notices),
    );
  }
}

/// Announcement cards, or the grey 8-ball when there are none.
class NoticesList extends ConsumerWidget {
  const NoticesList({super.key, required this.notices});

  final Future<List<Map<String, dynamic>>> notices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: notices,
      builder: (context, snap) {
        if (snap.hasError) {
          final offline = snap.error is ApiException;
          return Center(child: PcEmptyState(message: offline ? titleCase(t.offlineServer) : t.noticesLoadFail));
        }
        final items = snap.data;
        if (items == null) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (items.isEmpty) {
          return Center(child: PcEmptyState(message: titleCase(t.noticesEmpty)));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: items.length,
          itemBuilder: (context, i) => _NoticeCard(notice: items[i]),
        );
      },
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});

  final Map<String, dynamic> notice;

  @override
  Widget build(BuildContext context) {
    final banner = notice['kind'] == 'banner';
    return PcListRow(
      height: 0,
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(banner ? Icons.campaign_rounded : Icons.mail_rounded, color: banner ? DesignColors.pcGold : Colors.white, size: 44),
              const SizedBox(width: 14),
              Expanded(child: Text(titleCase(notice['title'] as String), style: pcText(34, color: banner ? DesignColors.pcGold : Colors.white))),
            ],
          ),
          const SizedBox(height: 12),
          Text(notice['body'] as String, style: pcText(28, color: const Color(0xFFE6E2FF), weight: FontWeight.w500, shadow: false).copyWith(height: 1.4)),
        ],
      ),
    );
  }
}
