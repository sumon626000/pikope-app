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
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import '../../data/api_client.dart';
import '../online/session.dart';
import '../start/login_screen.dart';
import 'legal_screen.dart';
import 'page_frame.dart';
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

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: ref.read(settingsProvider).name);
    if (Env.hasBackend) {
      _loadReferral();
      _loadSupport();
    }
  }

  Future<void> _loadReferral() async {
    try {
      await ref.read(sessionProvider.notifier).ensureSignedIn();
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
      await ref.read(sessionProvider.notifier).ensureSignedIn();
      await ref.read(apiProvider)!.post('/referral/apply', {'code': _invite.text.trim()});
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
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(22),
          decoration: duelPanel(rim: DuelColors.rimLight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout_rounded, color: DuelColors.red, size: 38),
              const SizedBox(height: 8),
              Text(t.logoutConfirmTitle, style: AppText.label(18, weight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                t.logoutConfirmBody,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'sans-serif', fontSize: 14, height: 1.4, color: DuelColors.silver),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DuelButton(
                    label: t.cancel,
                    width: 160,
                    height: 42,
                    fontSize: 16,
                    color: DuelColors.blue,
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                  const SizedBox(width: 12),
                  DuelButton(
                    label: t.logout,
                    width: 160,
                    height: 42,
                    fontSize: 16,
                    color: DuelColors.red,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    await ref.read(sessionProvider.notifier).logout();
    navigator.pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const LoginScreen()), (_) => false);
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
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) {
      showDuelMessage(context, title: t.sectionSupport, body: t.supportLinkMissing, icon: Icons.link_off_rounded);
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      showDuelMessage(context, title: t.sectionSupport, body: url, icon: Icons.open_in_new_rounded);
    }
  }

  Future<void> _saveName() async {
    final t = ref.read(stringsProvider);
    final name = _name.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_]{3,16}$').hasMatch(name)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.nicknameRulesError)));
      return;
    }
    if (!Env.hasBackend) {
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(name: name));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.nameSaved)));
      return;
    }
    setState(() => _savingName = true);
    try {
      await ref.read(sessionProvider.notifier).saveDisplayName(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.nameSaved)));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.maybeApi(e.message))));
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

  Widget _prefTile(String label, Widget control) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundAlt.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.frame.withValues(alpha: 0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.label(10, color: AppColors.textDim, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          control,
        ],
      ),
    );
  }

  Widget _challengeChip(String label, bool value, ValueChanged<bool> onChanged) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: value ? AppColors.active.withValues(alpha: 0.12) : AppColors.backgroundAlt.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: value ? AppColors.active : AppColors.frame, width: value ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(11, weight: FontWeight.w800, color: value ? AppColors.gold : AppColors.text),
              ),
            ),
            Transform.scale(
              scale: 0.78,
              child: Switch.adaptive(
                value: value,
                activeTrackColor: AppColors.gold.withValues(alpha: 0.45),
                activeThumbColor: AppColors.gold,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
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
      await ref.read(sessionProvider.notifier).ensureSignedIn();
      final r = await ref.read(apiProvider)!.patch('/me', {
        'challengesEnabled': s.challengesEnabled,
        'challengePoolEnabled': s.challengePoolEnabled,
        'challengeLudoEnabled': s.challengeLudoEnabled,
        'challengeCarromEnabled': s.challengeCarromEnabled,
      });
      ref.read(sessionProvider.notifier).adopt(r['user'] as Map<String, dynamic>);
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
      final file = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
      if (file == null) return;
      setState(() => _uploading = true);
      final bytes = await file.readAsBytes();
      if (Env.hasBackend) {
        await ref.read(sessionProvider.notifier).uploadAvatar(bytes, file.name);
      } else {
        final asset = await cloudinary.uploadImage(bytes, filename: file.name, subfolder: 'avatars');
        _update((s) => s.copyWith(avatar: 'cld:${asset.publicId}'));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).uploadFailed(e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
    return PageFrame(
      title: t.settingsTitle,
      maxWidth: 1080,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            compact: true,
            title: t.sectionPlayer,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FramedTile(size: 56, child: AvatarImage(s.avatar, size: 56)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.phone ?? t.noPhoneYet, style: AppText.label(15, weight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(t.winsGames(s.wins, s.games), style: AppText.label(10, color: AppColors.textDim)),
                          const SizedBox(width: 12),
                          const PikoCoinIcon(size: 15),
                          const SizedBox(width: 4),
                          Text(formatPicoCoins(s.coins), style: AppText.label(11, color: AppColors.gold, weight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _name,
                              enabled: canRename && !_savingName,
                              maxLength: 16,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_]'))],
                              style: AppText.label(14),
                              decoration: InputDecoration(
                                labelText: t.nicknameLabel,
                                counterText: '',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GameButton(
                            label: t.saveName,
                            height: 40,
                            width: 84,
                            fontSize: 11,
                            onPressed: canRename && !_savingName ? _saveName : null,
                          ),
                        ],
                      ),
                      Text(
                        canRename || next == null
                            ? t.nameEvery7
                            : t.nameNextChange(
                                '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}',
                              ),
                        style: AppText.label(9, color: AppColors.textDim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t.uploadPhoto, style: AppText.label(10, color: AppColors.textDim, weight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 42,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: DemoData.avatars.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (context, i) {
                            if (i == DemoData.avatars.length) {
                              return GameButton(
                                label: _uploading ? '…' : '+',
                                icon: Icons.cloud_upload_rounded,
                                height: 38,
                                width: 44,
                                fontSize: 10,
                                color: AppColors.frame,
                                onPressed: canUpload && !_uploading ? _uploadAvatar : null,
                              );
                            }
                            final a = DemoData.avatars[i];
                            return GestureDetector(
                              onTap: () => _update((st) => st.copyWith(avatar: a)),
                              child: FramedTile(
                                size: 38,
                                frameColor: a == s.avatar ? AppColors.active : AppColors.frame,
                                child: AvatarImage(a, size: 38),
                              ),
                            );
                          },
                        ),
                      ),
                      if (!canUpload) Text(t.uploadNeedsServer, style: AppText.label(9, color: AppColors.textDim)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: Env.hasBackend ? 1 : 2,
                child: SectionCard(
                  compact: true,
                  title: t.settingsPrefsBlock,
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _prefTile(
                              t.language,
                              ChoiceRow<String>(
                                dense: true,
                                options: {'en': t.languageEnglish, 'bn': t.languageBangla},
                                value: s.languageCode == 'bn' ? 'bn' : 'en',
                                onChanged: (v) => ref.read(settingsProvider.notifier).update((st) => st.copyWith(languageCode: v)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _prefTile(
                              t.sound,
                              ChoiceRow<bool>(
                                dense: true,
                                options: {true: t.on, false: t.off},
                                value: s.soundOn,
                                onChanged: (v) => _update((st) => st.copyWith(soundOn: v)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _prefTile(
                              t.sectionShotClock,
                              ChoiceRow<int>(
                                dense: true,
                                options: {20: t.secLabel(20), 30: t.secLabel(30), 45: t.secLabel(45), 60: t.secLabel(60)},
                                value: s.shotSeconds,
                                onChanged: (v) => _update((st) => st.copyWith(shotSeconds: v)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _prefTile(
                              t.sectionBot,
                              ChoiceRow<int>(
                                dense: true,
                                options: {0: t.botEasy, 1: t.botNormal, 2: t.botHard},
                                value: s.botLevel,
                                onChanged: (v) => _update((st) => st.copyWith(botLevel: v)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (Env.hasBackend) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      if (referral != null)
                      SectionCard(
                        compact: true,
                        title: t.sectionPlayerId,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('${referral['code']}', style: AppText.label(20, weight: FontWeight.w900)),
                                const SizedBox(width: 8),
                                GameButton(
                                  label: t.copy,
                                  height: 32,
                                  width: 64,
                                  fontSize: 10,
                                  color: AppColors.frame,
                                  onPressed: () => Clipboard.setData(ClipboardData(text: referral['code'] as String)),
                                ),
                                const Spacer(),
                                Text(t.invitedCount(referral['invited'] as int), style: AppText.label(10, weight: FontWeight.w800)),
                              ],
                            ),
                            Text(
                              '${t.referralEarn(referral['percent'] as int)} · ${t.referralTotals('${referral['earnedToday']}', '${referral['earnedMonth']}', '${referral['earned']}')}',
                              style: AppText.label(9, color: AppColors.textDim),
                            ),
                            const SizedBox(height: 4),
                            Text(t.playerIdHint, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.label(10, color: AppColors.text)),
                            if (referral['referredBy'] == null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _invite,
                                      maxLength: 6,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      style: AppText.label(14),
                                      decoration: InputDecoration(
                                        labelText: t.friendIdOptional,
                                        counterText: '',
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GameButton(
                                    label: _applying ? t.saving : t.useId,
                                    height: 36,
                                    width: 72,
                                    fontSize: 10,
                                    onPressed: _applying ? null : _applyInvite,
                                  ),
                                ],
                              ),
                              if (_inviteError != null)
                                Text(_inviteError!, style: AppText.label(10, color: AppColors.danger)),
                            ],
                          ],
                        ),
                      ),
                      SectionCard(
                        compact: true,
                        title: t.sectionChallenges,
                        child: Row(
                          children: [
                            _challengeChip(t.challengeReceivePool, s.challengePoolEnabled, (v) => _setChallengeFamily(ChallengeFamily.pool, v)),
                            const SizedBox(width: 6),
                            _challengeChip(t.challengeReceiveLudo, s.challengeLudoEnabled, (v) => _setChallengeFamily(ChallengeFamily.ludo, v)),
                            const SizedBox(width: 6),
                            _challengeChip(t.challengeReceiveCarrom, s.challengeCarromEnabled, (v) => _setChallengeFamily(ChallengeFamily.carrom, v)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          SectionCard(
            compact: true,
            title: '${t.sectionSupport} · ${t.sectionLegal}',
            child: Row(
              children: [
                Expanded(
                  child: GameButton(
                    label: t.facebookSupport,
                    icon: Icons.facebook_rounded,
                    height: 38,
                    width: double.infinity,
                    fontSize: 11,
                    color: const Color(0xFF1877F2),
                    onPressed: () => _openSupport(_facebook),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: GameButton(
                    label: t.telegramSupport,
                    icon: Icons.send_rounded,
                    height: 38,
                    width: double.infinity,
                    fontSize: 11,
                    color: const Color(0xFF229ED9),
                    onPressed: () => _openSupport(_telegram),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: GameButton(
                    label: t.privacy,
                    height: 38,
                    width: double.infinity,
                    fontSize: 10,
                    color: AppColors.frame,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LegalScreen(doc: LegalDoc.privacy))),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: GameButton(
                    label: t.terms,
                    height: 38,
                    width: double.infinity,
                    fontSize: 10,
                    color: AppColors.frame,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LegalScreen(doc: LegalDoc.terms))),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: GameButton(
                    label: t.conditions,
                    height: 38,
                    width: double.infinity,
                    fontSize: 10,
                    color: AppColors.frame,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LegalScreen(doc: LegalDoc.conditions))),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 120,
                  child: GameButton(
                    label: t.logout,
                    icon: Icons.logout_rounded,
                    height: 38,
                    width: double.infinity,
                    fontSize: 11,
                    color: AppColors.danger,
                    onPressed: _logout,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
