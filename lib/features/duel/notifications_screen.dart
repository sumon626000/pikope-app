import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../core/design/pool_city.dart';
import '../../core/duel_ui.dart';
import '../../data/api_client.dart';
import '../online/notification_unread.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import '../../l10n/strings.dart';

/// Player push inbox (deposit, redeem, challenge, admin messages) as the
/// reference's mail-style dialog.
Future<void> showNotificationsDialog(BuildContext context, WidgetRef ref) {
  final t = ref.read(stringsProvider);
  return showDuelDialog<void>(
    context,
    builder: (dialog) => PcDialog(
      title: t.notificationsTitle,
      width: 820,
      scroll: false,
      maxBodyHeight: 900,
      child: const SizedBox(height: 720, child: NotificationsList()),
    ),
  );
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return DuelPage(
      title: t.notificationsTitle,
      child: const NotificationsList(),
    );
  }
}

/// "Mark all read" plus the list, or the grey 8-ball when there is nothing.
class NotificationsList extends ConsumerStatefulWidget {
  const NotificationsList({super.key});

  @override
  ConsumerState<NotificationsList> createState() => _NotificationsListState();
}

class _NotificationsListState extends ConsumerState<NotificationsList> {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: PcButton(
            label: t.markAllRead,
            style: PcButtonStyle.gray,
            height: 70,
            fontSize: 26,
            onPressed: _markAllRead,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _load,
            builder: (context, snap) {
              if (snap.hasError) {
                final offline = snap.error is ApiException;
                return Center(
                  child: PcEmptyState(
                    message: offline
                        ? titleCase(t.offlineServer)
                        : t.notificationsLoadFail,
                  ),
                );
              }
              final items = snap.data;
              if (items == null) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }
              if (items.isEmpty) {
                return Center(
                  child: PcEmptyState(
                    message: titleCase(t.notificationsEmptyList),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: items.length,
                itemBuilder: (context, i) => _NotificationCard(item: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final read = item['read'] as bool? ?? false;
    return PcListRow(
      height: 0,
      me: !read,
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                read
                    ? Icons.notifications_none_rounded
                    : Icons.notifications_active_rounded,
                color: read ? DesignColors.pcTextDim : DesignColors.pcGold,
                size: 44,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  titleCase(item['title'] as String),
                  style: pcText(
                    34,
                    color: read ? Colors.white : DesignColors.pcGold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item['body'] as String,
            style: pcText(
              28,
              color: const Color(0xFFE6E2FF),
              weight: FontWeight.w500,
              shadow: false,
            ).copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}
