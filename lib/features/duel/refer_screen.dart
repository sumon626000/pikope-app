import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/design/design.dart';
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
      if (!await ref.read(sessionProvider.notifier).tryRestoreExistingSession()) {
        if (mounted) setState(() => _error = ref.read(stringsProvider).loginRequiredBody);
        return;
      }
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
    final phone = DesignBreakpoints.phoneLike(context);

    if (info == null) {
      final loading = Center(
        child: _error == null
            ? const CircularProgressIndicator(color: DuelColors.silver)
            : Text(_error!, textAlign: TextAlign.center, style: AppText.label(18, color: DuelColors.red)),
      );
      if (phone) {
        return _ReferPhoneShell(title: t.referTitle, sub: t.referSub, child: loading);
      }
      return DuelPage(title: t.referTitle, sub: t.referSub, child: loading);
    }

    final content = ReferScreenContent(
      info: info,
      t: t,
      phone: phone,
      friendController: _friend,
      applying: _applying,
      copied: _copied,
      error: _error,
      onCopy: _copy,
      onApply: _apply,
    );

    if (phone) {
      return _ReferPhoneShell(title: t.referTitle, sub: t.referSub, child: content);
    }

    return DuelPage(
      title: t.referTitle,
      sub: t.referSub,
      expanded: true,
      contentTop: 198,
      child: content,
    );
  }
}

/// Loaded refer UI (also used in layout tests with mock data).
@visibleForTesting
class ReferScreenContent extends StatelessWidget {
  const ReferScreenContent({
    super.key,
    required this.info,
    required this.t,
    required this.phone,
    required this.friendController,
    required this.applying,
    required this.copied,
    required this.error,
    required this.onCopy,
    required this.onApply,
  });

  final Map<String, dynamic> info;
  final AppStrings t;
  final bool phone;
  final TextEditingController friendController;
  final bool applying;
  final bool copied;
  final String? error;
  final void Function(String id) onCopy;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final id = info['code'] as String?;
    final people = (info['people'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IdCard(
          t: t,
          phone: phone,
          id: id,
          copied: copied,
          onCopy: onCopy,
        ),
        SizedBox(height: phone ? 6 : 8),
        Text(
          t.referFriendsEarnPct(info['percent'] as int),
          maxLines: phone ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'sans-serif',
            fontSize: phone ? 11 : 14,
            height: 1.35,
            color: DuelColors.dim,
          ),
        ),
        SizedBox(height: phone ? 8 : 16),
        _StatsRow(info: info, t: t, phone: phone),
        if (info['referredBy'] == null) ...[
          SizedBox(height: phone ? 8 : 16),
          _FriendApplyRow(
            t: t,
            phone: phone,
            controller: friendController,
            applying: applying,
            onApply: onApply,
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(error!, style: AppText.label(phone ? 12 : 14, color: DuelColors.red)),
          ),
        SizedBox(height: phone ? 8 : 12),
        if (people.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Text(
              t.referListHeader(people.length),
              style: AppText.label(phone ? 12 : 14, color: DuelColors.dim, weight: FontWeight.w800),
            ),
          ),
        Expanded(
          child: Container(
            decoration: duelPanel(radius: phone ? 12 : 16),
            padding: EdgeInsets.symmetric(horizontal: phone ? 10 : 18, vertical: phone ? 4 : 8),
            child: people.isEmpty
                ? Center(child: Text(t.noFriendsReferYet, style: AppText.label(phone ? 14 : 16, color: DuelColors.dim)))
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    cacheExtent: 400,
                    itemCount: people.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: const Color(0xFF1E2546).withValues(alpha: 0.85)),
                    itemBuilder: (_, i) => _ReferPersonRow(
                      index: i + 1,
                      name: '${people[i]['name']}',
                      earned: _earnedCoins(people[i]['earned']),
                      phone: phone,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  static int _earnedCoins(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }
}

class _ReferPhoneShell extends StatelessWidget {
  const _ReferPhoneShell({required this.title, required this.sub, required this.child});

  final String title;
  final String sub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DuelColors.ink,
      resizeToAvoidBottomInset: true,
      body: DuelBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignAuth.settingsPhonePaddingH,
              2,
              DesignAuth.settingsPhonePaddingH,
              4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).maybePop(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: DuelColors.rimLight, width: 1.2),
                            color: DuelColors.glass.withValues(alpha: 0.9),
                          ),
                          child: const Icon(Icons.arrow_back_rounded, color: DuelColors.silver, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppText.label(16, weight: FontWeight.w900)),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label(9, color: DuelColors.dim, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IdCard extends StatelessWidget {
  const _IdCard({
    required this.t,
    required this.phone,
    required this.id,
    required this.copied,
    required this.onCopy,
  });

  final AppStrings t;
  final bool phone;
  final String? id;
  final bool copied;
  final void Function(String id) onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 22, vertical: phone ? 10 : 16),
      decoration: duelPanel(radius: phone ? 12 : 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.playerId, style: AppText.label(phone ? 11 : 14, color: DuelColors.dim)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(id ?? '', style: AppText.label(phone ? 28 : 40, weight: FontWeight.w900)),
                ),
              ],
            ),
          ),
          DuelButton(
            label: copied ? t.copied : t.copy,
            icon: Icons.copy_rounded,
            width: phone ? 120 : 180,
            height: phone ? 40 : 52,
            fontSize: phone ? 14 : 18,
            onPressed: id == null ? null : () => onCopy(id!),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.info, required this.t, required this.phone});

  final Map<String, dynamic> info;
  final AppStrings t;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final boxes = [
      _StatBox(label: t.statInvited, value: '${info['invited']}', phone: phone),
      _StatBox(label: t.statToday, value: '${info['earnedToday']}', phone: phone),
      _StatBox(label: t.statThisMonth, value: '${info['earnedMonth']}', phone: phone),
      _StatBox(label: t.statTotal, value: '${info['earned']}', phone: phone),
    ];

    if (phone) {
      return Column(
        children: [
          Row(children: [Expanded(child: boxes[0]), const SizedBox(width: 8), Expanded(child: boxes[1])]),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: boxes[2]), const SizedBox(width: 8), Expanded(child: boxes[3])]),
        ],
      );
    }

    return Row(children: [for (final b in boxes) Expanded(child: b)]);
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, required this.phone});

  final String label;
  final String value;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(right: phone ? 0 : 10),
      padding: EdgeInsets.symmetric(vertical: phone ? 8 : 10),
      decoration: duelPanel(radius: phone ? 10 : 12),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppText.label(phone ? 16 : 22, weight: FontWeight.w900)),
          ),
          Text(label, textAlign: TextAlign.center, style: AppText.label(phone ? 9 : 11, color: DuelColors.dim)),
        ],
      ),
    );
  }
}

class _FriendApplyRow extends StatelessWidget {
  const _FriendApplyRow({
    required this.t,
    required this.phone,
    required this.controller,
    required this.applying,
    required this.onApply,
  });

  final AppStrings t;
  final bool phone;
  final TextEditingController controller;
  final bool applying;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      maxLength: 6,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: AppText.label(phone ? 16 : 20),
      decoration: InputDecoration(labelText: t.friendIdOptional, counterText: ''),
    );
    final btn = DuelButton(
      label: applying ? t.saving : t.useId,
      width: phone ? double.infinity : 180,
      height: phone ? 42 : 52,
      fontSize: phone ? 15 : 18,
      color: DuelColors.blue,
      onPressed: applying ? null : onApply,
    );

    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [field, const SizedBox(height: 8), btn],
      );
    }

    return Row(
      children: [
        SizedBox(width: 360, child: field),
        const SizedBox(width: 16),
        btn,
      ],
    );
  }
}

class _ReferPersonRow extends StatelessWidget {
  const _ReferPersonRow({
    required this.index,
    required this.name,
    required this.earned,
    required this.phone,
  });

  final int index;
  final String name;
  final int earned;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: phone ? 6 : 4),
      child: Row(
        children: [
          SizedBox(
            width: phone ? 22 : 28,
            child: Text('$index.', style: AppText.label(phone ? 11 : 13, color: DuelColors.dim)),
          ),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label(phone ? 14 : 16),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PikoCoinIcon(size: phone ? 18 : 20),
              const SizedBox(width: 4),
              Text(
                formatCoins(earned, compact: earned >= 100000),
                style: AppText.label(phone ? 13 : 15, color: DuelColors.gold, weight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
