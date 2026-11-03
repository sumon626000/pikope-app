import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_state.dart';
import '../duel/challenge_prefs.dart';
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: duelPanel(radius: 18, rim: DuelColors.rimLight, glow: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: DuelColors.gold.withValues(alpha: 0.12),
                  border: Border.all(
                    color: DuelColors.gold.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(icon, color: DuelColors.gold, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppText.label(16, weight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
      label,
      style: AppText.label(13, color: DuelColors.dim, weight: FontWeight.w800),
    );
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [title, const SizedBox(height: 8), control],
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
    final stackPrefs = phoneLayout;
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
                dense: true,
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
                dense: true,
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
                dense: true,
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
                dense: true,
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

    if (phoneLayout) {
      return _SettingsPhoneShell(title: t.settingsTitle, child: body);
    }

    return DuelPage(
      title: t.settingsTitle,
      expanded: true,
      sideBack: true,
      contentTop: DesignSecondaryPage.bodyTopExpanded,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: DesignSpacing.x3),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignAuth.settingsContentMaxWidth,
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _profileHeader(
    AppSettings s,
    SessionState session,
    AppStrings t, {
    required bool compact,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 68 : 76,
          height: compact ? 68 : 76,
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFE08A), Color(0xFF5C8BFF), Color(0xFFFF3B4E)],
            ),
          ),
          child: ClipOval(
            child: AvatarImage(s.avatar, size: compact ? 62 : 70),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.phone ?? t.noPhoneYet,
                style: AppText.label(
                  compact ? 16 : 17,
                  weight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.winsGames(s.wins, s.games),
                style: AppText.label(12, color: DuelColors.dim),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  PikoCoinIcon(size: compact ? 18 : 20),
                  const SizedBox(width: 6),
                  Text(
                    formatPicoCoins(s.coins),
                    style: AppText.label(
                      compact ? 14 : 15,
                      color: DuelColors.gold,
                      weight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
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

/// Full-screen settings on phones — uses the real viewport instead of scaling 1600×900.
class _SettingsPhoneShell extends StatelessWidget {
  const _SettingsPhoneShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DuelColors.ink,
      resizeToAvoidBottomInset: true,
      body: DuelBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 10, 0),
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).maybePop(),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: DuelColors.rimLight,
                              width: 1.5,
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                DuelColors.glass,
                                DuelColors.glass.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: DuelColors.silver,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppText.label(22, weight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 46),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignAuth.settingsPhonePaddingH,
                  8,
                  DesignAuth.settingsPhonePaddingH,
                  6,
                ),
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    gradient: LinearGradient(
                      colors: [
                        DuelColors.gold.withValues(alpha: 0.05),
                        DuelColors.gold.withValues(alpha: 0.55),
                        DuelColors.gold.withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  radius: const Radius.circular(8),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      DesignAuth.settingsPhonePaddingH,
                      4,
                      DesignAuth.settingsPhonePaddingH,
                      DesignAuth.settingsPhonePaddingBottom,
                    ),
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
