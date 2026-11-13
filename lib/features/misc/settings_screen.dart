import 'package:flutter/material.dart';
import '../../core/design/pool_city.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_state.dart';
import '../duel/challenge_prefs.dart';
import '../duel/home_portrait_widgets.dart' show RankEmblemPainter;
import '../../core/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/demo_data.dart';
import '../../core/design/design.dart';
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import '../../data/api_client.dart';
import '../online/session.dart';
import '../duel/duel_chrome.dart';
import '../start/loading_screen.dart';
import 'legal_screen.dart';
import 'page_frame.dart';
import 'profile_match_stats.dart';
import '../../l10n/strings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _name;
  final _invite = TextEditingController();
  bool _uploading = false;
  bool _savingName = false;
  bool _applying = false;
  Map<String, dynamic>? _referral;
  String? _inviteError;
  String _facebook = '';
  String _telegram = '';
  Map<String, dynamic>? _matchStats;
  bool _statsLoading = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: ref.read(settingsProvider).name);
    if (Env.hasBackend) {
      _loadReferral();
      _loadSupport();
      _loadMatchStats();
    }
  }

  Future<void> _loadMatchStats() async {
    setState(() => _statsLoading = true);
    try {
      final session = ref.read(sessionProvider.notifier);
      if (await session.tryRestoreExistingSession()) {
        final raw = await session.playerMatchStats();
        if (mounted) setState(() => _matchStats = raw);
      }
    } catch (_) {
      // Fall back to local wins/games on profile card.
    } finally {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  ({
    int games,
    int wins,
    int losses,
    int winRate,
    int todayPlayed,
    int todayWins,
    int todayLosses,
  })
  _resolvedStats(AppSettings s) {
    final m = _matchStats;
    if (m != null) {
      final games = (m['totalGames'] as num?)?.toInt() ?? s.games;
      final wins = (m['totalWins'] as num?)?.toInt() ?? s.wins;
      final losses =
          (m['totalLosses'] as num?)?.toInt() ?? (games - wins).clamp(0, games);
      return (
        games: games,
        wins: wins,
        losses: losses,
        winRate:
            (m['winRate'] as num?)?.toInt() ??
            (games == 0 ? 0 : (100 * wins / games).round()),
        todayPlayed: (m['todayPlayed'] as num?)?.toInt() ?? 0,
        todayWins: (m['todayWins'] as num?)?.toInt() ?? 0,
        todayLosses: (m['todayLosses'] as num?)?.toInt() ?? 0,
      );
    }
    final games = s.games;
    final wins = s.wins;
    final losses = (games - wins).clamp(0, games);
    return (
      games: games,
      wins: wins,
      losses: losses,
      winRate: games == 0 ? 0 : (100 * wins / games).round(),
      todayPlayed: 0,
      todayWins: 0,
      todayLosses: 0,
    );
  }

  Future<void> _loadReferral() async {
    try {
      if (!await ref.read(sessionProvider.notifier).tryRestoreExistingSession())
        return;
      final info = await ref.read(apiProvider)!.get('/referral');
      if (mounted) setState(() => _referral = info);
    } catch (_) {
      // The rest of settings still works if the invite card cannot load.
    }
  }

  Future<void> _applyInvite() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_invite.text.trim())) return;
    setState(() {
      _applying = true;
      _inviteError = null;
    });
    try {
      if (!await ref.read(sessionProvider.notifier).tryRestoreExistingSession())
        return;
      await ref.read(apiProvider)!.post('/referral/apply', {
        'code': _invite.text.trim(),
      });
      final info = await ref.read(apiProvider)!.get('/referral');
      if (mounted) setState(() => _referral = info);
    } on ApiException catch (e) {
      if (mounted) setState(() => _inviteError = e.message);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    final t = ref.read(stringsProvider);
    final ok = await showDuelDialog<bool>(
      context,
      builder: (ctx) => DesignPromptDialog(
        rim: DuelColors.rimLight,
        icon: const Icon(Icons.logout_rounded, color: DuelColors.red, size: 38),
        title: t.logoutConfirmTitle,
        body: t.logoutConfirmBody,
        actions: [
          DesignCompactButton(
            label: t.cancel,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          DesignCompactButton(
            label: t.logout,
            color: DuelColors.red,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    await ref.read(sessionProvider.notifier).logout();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoadingScreen()),
      (_) => false,
    );
  }

  Future<void> _loadSupport() async {
    final api = ref.read(apiProvider);
    if (api == null) return;
    try {
      final j = await api.get('/config');
      if (!mounted) return;
      setState(() {
        _facebook = (j['facebook'] as String?)?.trim() ?? '';
        _telegram = (j['telegram'] as String?)?.trim() ?? '';
      });
    } catch (_) {}
  }

  Future<void> _openSupport(String url) async {
    final t = ref.read(stringsProvider);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme('https') || uri.isScheme('http')) ||
        uri.host.isEmpty) {
      showDuelMessage(
        context,
        title: t.sectionSupport,
        body: t.supportLinkMissing,
        icon: Icons.link_off_rounded,
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      showDuelMessage(
        context,
        title: t.sectionSupport,
        body: url,
        icon: Icons.open_in_new_rounded,
      );
    }
  }

  Future<void> _saveName() async {
    final t = ref.read(stringsProvider);
    final name = _name.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_]{3,16}$').hasMatch(name)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.nicknameRulesError)));
      return;
    }
    if (!Env.hasBackend) {
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(name: name));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.nameSaved)));
      return;
    }
    setState(() => _savingName = true);
    try {
      await ref.read(sessionProvider.notifier).saveDisplayName(name);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.nameSaved)));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.maybeApi(e.message))));
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  void _update(AppSettings Function(AppSettings) change) {
    ref.read(settingsProvider.notifier).update(change);
    // Signed in: the server keeps the same name, avatar and table.
    ref.read(sessionProvider.notifier).pushProfile();
  }

  Widget _settingsCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    // Reference settings: a plain white heading with a rule, rows beneath.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(titleCase(title), style: pcText(17))),
            ],
          ),
          const SizedBox(height: 4),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _cardDivider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Divider(
      height: 1,
      color: DuelColors.rimLight.withValues(alpha: 0.32),
    ),
  );

  Widget _prefInline(String label, Widget control, {required bool stack}) {
    final title = Text(
      titleCase(label),
      style: pcText(14, color: const Color(0xFFD9D2FF)),
    );
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [title, const SizedBox(height: 5), control],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 2, child: title),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: control),
      ],
    );
  }

  Widget _compactLink({
    required String label,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: accent.withValues(alpha: 0.1),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(13, weight: FontWeight.w800),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: DuelColors.dim.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _challengeChip(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    bool stacked = false,
  }) {
    if (stacked) {
      // Reference style: label over an ON / OFF bar.
      final t = ref.read(stringsProvider);
      return _prefInline(
        label,
        ChoiceRow<bool>(mini: true, options: {true: t.on, false: t.off}, value: value, onChanged: onChanged),
        stack: true,
      );
    }
    final chip = Container(
      width: stacked ? double.infinity : null,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignSpacing.x2,
        vertical: DesignSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: value
            ? AppColors.active.withValues(alpha: 0.12)
            : AppColors.backgroundAlt.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(DesignRadii.sm),
        border: Border.all(
          color: value ? AppColors.active : AppColors.frame,
          width: value ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.label(
                13,
                weight: FontWeight.w800,
                color: value ? AppColors.gold : AppColors.text,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.88,
            child: Switch.adaptive(
              value: value,
              activeTrackColor: AppColors.gold.withValues(alpha: 0.45),
              activeThumbColor: AppColors.gold,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
    return stacked ? chip : Expanded(child: chip);
  }

  Future<void> _setChallengeFamily(ChallengeFamily family, bool on) async {
    AppSettings next(AppSettings s) {
      final patched = switch (family) {
        ChallengeFamily.pool => s.copyWith(challengePoolEnabled: on),
        ChallengeFamily.ludo => s.copyWith(challengeLudoEnabled: on),
        ChallengeFamily.carrom => s.copyWith(challengeCarromEnabled: on),
      };
      final any = anyChallengeReceiveEnabled(patched);
      return patched.copyWith(challengesEnabled: any);
    }

    _update(next);
    if (!Env.hasBackend) return;
    final s = ref.read(settingsProvider);
    try {
      if (!await ref.read(sessionProvider.notifier).tryRestoreExistingSession())
        return;
      final r = await ref.read(apiProvider)!.patch('/me', {
        'challengesEnabled': s.challengesEnabled,
        'challengePoolEnabled': s.challengePoolEnabled,
        'challengeLudoEnabled': s.challengeLudoEnabled,
        'challengeCarromEnabled': s.challengeCarromEnabled,
      });
      ref
          .read(sessionProvider.notifier)
          .adopt(r['user'] as Map<String, dynamic>);
    } on ApiException {
      // Local preference still applies for popups on this device.
    }
  }

  /// With a game server the photo is stored there; otherwise on Cloudinary
  /// when that is configured.
  Future<void> _uploadAvatar() async {
    final messenger = ScaffoldMessenger.of(context);
    final cloudinary = ref.read(cloudinaryProvider);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null) return;
      setState(() => _uploading = true);
      final bytes = await file.readAsBytes();
      if (Env.hasBackend) {
        await ref.read(sessionProvider.notifier).uploadAvatar(bytes, file.name);
      } else {
        final asset = await cloudinary.uploadImage(
          bytes,
          filename: file.name,
          subfolder: 'avatars',
        );
        _update((s) => s.copyWith(avatar: 'cld:${asset.publicId}'));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(ref.read(stringsProvider).uploadFailed(e))),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _avatarPicker(AppSettings s, bool canUpload) {
    final t = ref.watch(stringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.uploadPhoto,
          style: AppText.label(
            13,
            color: DuelColors.dim,
            weight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: DemoData.avatars.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              if (i == DemoData.avatars.length) {
                return GameButton(
                  label: _uploading ? '…' : t.uploadPhoto,
                  icon: Icons.cloud_upload_rounded,
                  height: 44,
                  width: 118,
                  fontSize: 12,
                  color: DuelColors.blue,
                  onPressed: canUpload && !_uploading ? _uploadAvatar : null,
                );
              }
              final a = DemoData.avatars[i];
              final selected = a == s.avatar;
              return GestureDetector(
                onTap: () => _update((st) => st.copyWith(avatar: a)),
                child: Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? DuelColors.green : DuelColors.rim,
                      width: selected ? 2.5 : 1.5,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: DuelColors.green.withValues(alpha: 0.35),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipOval(child: AvatarImage(a, size: 40)),
                ),
              );
            },
          ),
        ),
        if (!canUpload)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              t.uploadNeedsServer,
              style: AppText.label(11, color: DuelColors.dim),
            ),
          ),
      ],
    );
  }

  Widget _supportLinksGrid(
    BuildContext context, {
    required String facebook,
    required String telegram,
  }) {
    final t = ref.watch(stringsProvider);
    final nav = Navigator.of(context);
    final links = <Widget>[
      _compactLink(
        label: t.facebookSupport,
        icon: Icons.facebook_rounded,
        accent: const Color(0xFF1877F2),
        onTap: () => _openSupport(facebook),
      ),
      _compactLink(
        label: t.telegramSupport,
        icon: Icons.send_rounded,
        accent: const Color(0xFF229ED9),
        onTap: () => _openSupport(telegram),
      ),
      _compactLink(
        label: t.privacy,
        icon: Icons.privacy_tip_outlined,
        accent: DuelColors.blue,
        onTap: () => nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const LegalScreen(doc: LegalDoc.privacy),
          ),
        ),
      ),
      _compactLink(
        label: t.terms,
        icon: Icons.description_outlined,
        accent: DuelColors.silver,
        onTap: () => nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const LegalScreen(doc: LegalDoc.terms),
          ),
        ),
      ),
      _compactLink(
        label: t.conditions,
        icon: Icons.gavel_rounded,
        accent: DuelColors.silver,
        onTap: () => nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const LegalScreen(doc: LegalDoc.conditions),
          ),
        ),
      ),
      _compactLink(
        label: t.logout,
        icon: Icons.logout_rounded,
        accent: DuelColors.red,
        onTap: _logout,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final twoCol = c.maxWidth >= 340;
        const gap = 8.0;
        if (!twoCol) {
          return Column(
            children: [
              for (var i = 0; i < links.length; i++) ...[
                if (i > 0) const SizedBox(height: gap),
                links[i],
              ],
            ],
          );
        }
        final cellW = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final link in links) SizedBox(width: cellW, child: link),
          ],
        );
      },
    );
  }

  Widget _referralSection(Map<String, dynamic> referral) {
    final t = ref.watch(stringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.sectionPlayerId,
          style: AppText.label(
            14,
            weight: FontWeight.w900,
            color: DuelColors.gold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${referral['code']}',
                style: AppText.label(28, weight: FontWeight.w900),
              ),
            ),
            GameButton(
              label: t.copy,
              height: 40,
              width: 88,
              fontSize: 13,
              color: DuelColors.blue,
              onPressed: () => Clipboard.setData(
                ClipboardData(text: referral['code'] as String),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          t.invitedCount(referral['invited'] as int),
          style: AppText.label(12, weight: FontWeight.w800),
        ),
        Text(
          '${t.referralEarn(referral['percent'] as int)} · ${t.referralTotals('${referral['earnedToday']}', '${referral['earnedMonth']}', '${referral['earned']}')}',
          style: AppText.label(11, color: DuelColors.dim),
        ),
        const SizedBox(height: 8),
        Text(
          t.playerIdHint,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppText.label(12, color: DuelColors.silver),
        ),
        if (referral['referredBy'] == null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _invite,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppText.label(16),
                  decoration: InputDecoration(
                    labelText: t.friendIdOptional,
                    counterText: '',
                    filled: true,
                    fillColor: DesignAuth.fieldFillLobby,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GameButton(
                label: _applying ? t.saving : t.useId,
                height: 44,
                width: 96,
                fontSize: 12,
                onPressed: _applying ? null : _applyInvite,
              ),
            ],
          ),
          if (_inviteError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _inviteError!,
                style: AppText.label(11, color: DuelColors.red),
              ),
            ),
        ],
      ],
    );
  }

  Widget _settingsScrollBody({
    required BuildContext context,
    required bool phoneLayout,
    required AppSettings s,
    required SessionState session,
    required AppStrings t,
    required bool canRename,
    required DateTime? next,
    required bool canUpload,
    required Map<String, dynamic>? referral,
  }) {
    final gap = phoneLayout
        ? DesignAuth.settingsPhoneSectionGap
        : DesignAuth.settingsSectionGap;
    const stackPrefs = true;
    final st = _resolvedStats(s);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _settingsCard(
          title: t.sectionAccount,
          icon: Icons.account_circle_rounded,
          children: [
            _profileHeader(s, session, t, compact: phoneLayout),
            _cardDivider(),
            ProfileMatchStatsPanel(
              totalGames: st.games,
              totalWins: st.wins,
              totalLosses: st.losses,
              winRate: st.winRate,
              todayPlayed: st.todayPlayed,
              todayWins: st.todayWins,
              todayLosses: st.todayLosses,
              loading: Env.hasBackend && _statsLoading && _matchStats == null,
              compactHeader: true,
            ),
            _cardDivider(),
            _nicknameRow(t, canRename, next),
            _cardDivider(),
            _avatarPicker(s, canUpload),
            if (Env.hasBackend && referral != null) ...[
              _cardDivider(),
              _referralSection(referral),
            ],
          ],
        ),
        SizedBox(height: gap),
        _settingsCard(
          title: t.settingsPrefsBlock,
          icon: Icons.sports_esports_rounded,
          children: [
            _prefInline(
              t.language,
              ChoiceRow<String>(
                mini: true,
                options: {'en': t.languageEnglish, 'bn': t.languageBangla},
                value: s.languageCode == 'bn' ? 'bn' : 'en',
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .update((st) => st.copyWith(languageCode: v)),
              ),
              stack: stackPrefs,
            ),
            _cardDivider(),
            _prefInline(
              t.sound,
              ChoiceRow<bool>(
                mini: true,
                options: {true: t.on, false: t.off},
                value: s.soundOn,
                onChanged: (v) => _update((st) => st.copyWith(soundOn: v)),
              ),
              stack: stackPrefs,
            ),
            _cardDivider(),
            _prefInline(
              t.sectionShotClock,
              ChoiceRow<int>(
                mini: true,
                options: {
                  20: t.secLabel(20),
                  30: t.secLabel(30),
                  45: t.secLabel(45),
                  60: t.secLabel(60),
                },
                value: s.shotSeconds,
                onChanged: (v) => _update((st) => st.copyWith(shotSeconds: v)),
              ),
              stack: stackPrefs,
            ),
            _cardDivider(),
            _prefInline(
              t.sectionBot,
              ChoiceRow<int>(
                mini: true,
                options: {0: t.botEasy, 1: t.botNormal, 2: t.botHard},
                value: s.botLevel,
                onChanged: (v) => _update((st) => st.copyWith(botLevel: v)),
              ),
              stack: stackPrefs,
            ),
            if (Env.hasBackend) ...[
              _cardDivider(),
              Text(
                t.sectionChallenges,
                style: AppText.label(
                  13,
                  weight: FontWeight.w900,
                  color: DuelColors.gold,
                ),
              ),
              const SizedBox(height: 8),
              phoneLayout
                  ? Column(
                      children: [
                        _challengeChip(
                          t.challengeReceivePool,
                          s.challengePoolEnabled,
                          (v) => _setChallengeFamily(ChallengeFamily.pool, v),
                          stacked: true,
                        ),
                        const SizedBox(height: 8),
                        _challengeChip(
                          t.challengeReceiveLudo,
                          s.challengeLudoEnabled,
                          (v) => _setChallengeFamily(ChallengeFamily.ludo, v),
                          stacked: true,
                        ),
                        const SizedBox(height: 8),
                        _challengeChip(
                          t.challengeReceiveCarrom,
                          s.challengeCarromEnabled,
                          (v) => _setChallengeFamily(ChallengeFamily.carrom, v),
                          stacked: true,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        _challengeChip(
                          t.challengeReceivePool,
                          s.challengePoolEnabled,
                          (v) => _setChallengeFamily(ChallengeFamily.pool, v),
                        ),
                        const SizedBox(width: 8),
                        _challengeChip(
                          t.challengeReceiveLudo,
                          s.challengeLudoEnabled,
                          (v) => _setChallengeFamily(ChallengeFamily.ludo, v),
                        ),
                        const SizedBox(width: 8),
                        _challengeChip(
                          t.challengeReceiveCarrom,
                          s.challengeCarromEnabled,
                          (v) => _setChallengeFamily(ChallengeFamily.carrom, v),
                        ),
                      ],
                    ),
            ],
          ],
        ),
        SizedBox(height: gap),
        _settingsCard(
          title: '${t.sectionSupport} · ${t.sectionLegal}',
          icon: Icons.support_agent_rounded,
          children: [
            _supportLinksGrid(
              context,
              facebook: _facebook,
              telegram: _telegram,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final t = ref.watch(stringsProvider);
    final canRename = !Env.hasBackend || session.canChangeName;
    final next = session.nameChangeAllowedAt?.toLocal();
    final canUpload = Env.hasBackend || ref.watch(cloudinaryProvider).canUpload;
    final referral = _referral;
    final phoneLayout = DesignBreakpoints.phoneLike(context);

    final body = _settingsScrollBody(
      context: context,
      phoneLayout: phoneLayout,
      s: s,
      session: session,
      t: t,
      canRename: canRename,
      next: next,
      canUpload: canUpload,
      referral: referral,
    );

    // One portrait layout (Pool City page): the body scrolls on the panel.
    return DuelPage(
      title: t.settingsTitle,
      scroll: true,
      child: PcLegacyScale(child: body),
    );
  }

  Widget _profileHeader(
    AppSettings s,
    SessionState session,
    AppStrings t, {
    required bool compact,
  }) {
    final avatarSize = compact ? 72.0 : 82.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar in a cyan-rimmed frame.
        Container(
          width: avatarSize,
          height: avatarSize,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8FD0FF), Color(0xFF5E86F0), Color(0xFF6E5BD6)],
            ),
            border: Border.all(color: const Color(0xFF29C6F0), width: 2.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: AvatarImage(s.avatar, size: avatarSize - 7),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(compact ? 16 : 18, weight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                session.phone ?? t.noPhoneYet,
                style: AppText.label(11, color: DuelColors.dim),
              ),
              const SizedBox(height: 6),
              _levelBar(session, compact: compact),
              const SizedBox(height: 7),
              Row(
                children: [
                  PikoCoinIcon(size: compact ? 16 : 18),
                  const SizedBox(width: 6),
                  Text(
                    formatPicoCoins(s.coins),
                    style: AppText.label(
                      compact ? 13 : 15,
                      color: DuelColors.gold,
                      weight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // Rank emblem.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: compact ? 54 : 62,
              height: compact ? 58 : 68,
              child: CustomPaint(
                painter: RankEmblemPainter(
                  session.signedIn ? session.rankTier : -1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: compact ? 64 : 74,
              child: Text(
                titleCase(session.rankName),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(compact ? 10 : 12, weight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _levelBar(SessionState session, {required bool compact}) {
    final circle = compact ? 28.0 : 34.0;
    return Stack(
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.none,
      children: [
        Container(
          height: compact ? 16 : 20,
          margin: EdgeInsets.only(left: circle / 2),
          decoration: BoxDecoration(
            color: const Color(0xFF1B2247),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              FractionallySizedBox(
                widthFactor: (session.levelProgress / 100).clamp(0.04, 1.0),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF3CCB5A), Color(0xFF2AA54A)],
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  '${session.levelProgress}%',
                  style: AppText.label(compact ? 9 : 11, weight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: circle,
          height: circle,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [Color(0xFFFFE27A), Color(0xFFE09A12)]),
          ),
          child: Text(
            '${session.level}',
            style: AppText.label(compact ? 12 : 15, weight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  Widget _nicknameRow(AppStrings t, bool canRename, DateTime? next) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _name,
                enabled: canRename && !_savingName,
                maxLength: 16,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_]')),
                ],
                style: AppText.label(16),
                decoration: DesignAuth.fieldDecoration(
                  t.nicknameLabel,
                  dense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            GameButton(
              label: t.saveName,
              height: 44,
              width: 100,
              fontSize: 12,
              onPressed: canRename && !_savingName ? _saveName : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          canRename || next == null
              ? t.nameEvery7
              : t.nameNextChange(
                  '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}',
                ),
          style: AppText.label(11, color: DuelColors.dim),
        ),
      ],
    );
  }
}
