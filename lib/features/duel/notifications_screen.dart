import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../data/api_client.dart';
import '../online/notification_unread.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import '../../l10n/strings.dart';

/// Player push inbox (deposit, redeem, challenge, admin messages).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late Future<List<Map<String, dynamic>>> _load;

  @override
  void initState() {
    super.initState();
    _load = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final j = await ref.read(sessionProvider.notifier).notifications();
    ref.read(notificationUnreadProvider.notifier).set(j['unread'] as int? ?? 0);
    return (j['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> _markAllRead() async {
    await ref.read(sessionProvider.notifier).markNotificationsRead();
    ref.read(notificationUnreadProvider.notifier).set(0);
    setState(() => _load = _fetch());
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return DuelPage(
      title: t.notificationsTitle,
      sub: t.notificationsSub,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _markAllRead,
              child: Text(t.markAllRead, style: AppText.label(14, color: DuelColors.silver)),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _load,
              builder: (context, snap) {
                if (snap.hasError) {
                  final offline = snap.error is ApiException;
                  return Center(
                    child: Text(
                      offline ? t.offlineServer : t.notificationsLoadFail,
                      style: AppText.label(18, color: DuelColors.red),
                    ),
                  );
                }
                final items = snap.data;
                if (items == null) {
                  return const Center(child: CircularProgressIndicator(color: DuelColors.silver));
                }
                if (items.isEmpty) {
                  return Center(child: Text(t.notificationsEmptyList, style: AppText.label(20, color: DuelColors.dim)));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _NotificationCard(item: items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final read = item['read'] as bool? ?? false;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: duelPanel(radius: 14, rim: read ? DuelColors.rim : DuelColors.gold),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                read ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
                color: read ? DuelColors.dim : DuelColors.gold,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  (item['title'] as String).toUpperCase(),
                  style: AppText.label(18, color: read ? DuelColors.silver : DuelColors.gold, weight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(item['body'] as String, style: AppText.label(16, color: DuelColors.silver)),
        ],
      ),
    );
  }
}
