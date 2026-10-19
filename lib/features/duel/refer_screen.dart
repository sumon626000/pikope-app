import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import '../../data/api_client.dart';
import '../online/session.dart';
import 'duel_chrome.dart';
import '../../l10n/strings.dart';

/// The player's 6-digit ID. Friends enter this same number as a refer code.
class ReferScreen extends ConsumerStatefulWidget {
  const ReferScreen({super.key});

  @override
  ConsumerState<ReferScreen> createState() => _ReferScreenState();
}

class _ReferScreenState extends ConsumerState<ReferScreen> {
  final _friend = TextEditingController();
  Map<String, dynamic>? _info;
  String? _error;
  bool _applying = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _friend.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!Env.hasBackend) {
      setState(() => _error = ref.read(stringsProvider).referNeedServer);
      return;
    }
    try {
      await ref.read(sessionProvider.notifier).ensureSignedIn();
      final info = await ref.read(apiProvider)!.get('/referral');
      if (mounted) setState(() => _info = info);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = ref.read(stringsProvider).maybeApi(e.message));
    } catch (_) {
      if (mounted) setState(() => _error = ref.read(stringsProvider).referLoadFail);
    }
  }

  Future<void> _apply() async {
    final code = _friend.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = ref.read(stringsProvider).referFriendId6);
      return;
    }
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider)!.post('/referral/apply', {'code': code});
      final info = await ref.read(apiProvider)!.get('/referral');
      if (mounted) setState(() => _info = info);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = ref.read(stringsProvider).maybeApi(e.message));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _copy(String id) {
    Clipboard.setData(ClipboardData(text: id));
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final info = _info;
    final id = info?['code'] as String?;
    final people = (info?['people'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
    return DuelPage(
      title: t.referTitle,
      sub: t.referSub,
      child: info == null
          ? Center(child: _error == null
              ? const CircularProgressIndicator(color: DuelColors.silver)
              : Text(_error!, textAlign: TextAlign.center, style: AppText.label(18, color: DuelColors.red)))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  decoration: duelPanel(radius: 16),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.playerId, style: AppText.label(14, color: DuelColors.dim)),
                          const SizedBox(height: 4),
                          Text(id ?? '', style: AppText.label(40, weight: FontWeight.w900)),
                        ],
                      ),
                      const Spacer(),
                      DuelButton(
                        label: _copied ? t.copied : t.copy,
                        icon: Icons.copy_rounded,
                        width: 180,
                        height: 52,
                        fontSize: 18,
                        onPressed: id == null ? null : () => _copy(id),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.referFriendsEarnPct(info['percent'] as int),
                  style: const TextStyle(fontFamily: 'sans-serif', fontSize: 14, height: 1.35, color: DuelColors.dim),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _box(t.statInvited, '${info['invited']}'),
                    _box(t.statToday, '${info['earnedToday']}'),
                    _box(t.statThisMonth, '${info['earnedMonth']}'),
                    _box(t.statTotal, '${info['earned']}'),
                  ],
                ),
                if (info['referredBy'] == null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SizedBox(
                        width: 360,
                        child: TextField(
                          controller: _friend,
                          maxLength: 6,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: AppText.label(20),
                          decoration: InputDecoration(
                            labelText: t.friendIdOptional,
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      DuelButton(
                        label: _applying ? t.saving : t.useId,
                        width: 180,
                        height: 52,
                        fontSize: 18,
                        color: DuelColors.blue,
                        onPressed: _applying ? null : _apply,
                      ),
                    ],
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: AppText.label(14, color: DuelColors.red)),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: duelPanel(radius: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: people.isEmpty
                        ? Center(child: Text(t.noFriendsReferYet, style: AppText.label(16, color: DuelColors.dim)))
                        : ListView.separated(
                            itemCount: people.length,
                            separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF1E2546)),
                            itemBuilder: (_, i) {
                              final p = people[i];
                              return SizedBox(
                                height: 48,
                                child: Row(
                                  children: [
                                    Expanded(child: Text('${p['name']}', style: AppText.label(16))),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const PikoCoinIcon(size: 20),
                                        const SizedBox(width: 6),
                                        Text('${p['earned']}', style: AppText.label(15, color: DuelColors.gold)),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _box(String label, String value) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: duelPanel(radius: 12),
          child: Column(
            children: [
              Text(value, style: AppText.label(22, weight: FontWeight.w900)),
              Text(label, style: AppText.label(11, color: DuelColors.dim)),
            ],
          ),
        ),
      );
}
