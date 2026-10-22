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

  Widget _challengeSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFF1A2038), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontFamily: 'sans-serif', fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
          Switch.adaptive(value: value, activeColor: AppColors.gold, onChanged: onChanged),
        ],
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
    return PageFrame(
      title: t.settingsTitle,
      child: Column(
        children: [
          SectionCard(
            title: t.language,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.languageHint,
                    style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, height: 1.4, color: AppColors.text)),
                const SizedBox(height: 12),
                ChoiceRow<String>(
                  options: { 'en': t.languageEnglish, 'bn': t.languageBangla },
                  value: s.languageCode == 'bn' ? 'bn' : 'en',
                  onChanged: (v) => ref.read(settingsProvider.notifier).update((st) => st.copyWith(languageCode: v)),
                ),
              ],
            ),
          ),
          SectionCard(
            title: t.sectionPlayer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.phoneShown, style: AppText.label(12, color: AppColors.textDim)),
                const SizedBox(height: 4),
                Text(
                  session.phone ?? t.noPhoneYet,
                  style: AppText.label(20, weight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FramedTile(size: 72, child: AvatarImage(s.avatar, size: 72)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _name,
                        enabled: canRename && !_savingName,
                        maxLength: 16,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_]'))],
                        style: AppText.label(18),
                        decoration: InputDecoration(labelText: t.nicknameLabel, counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GameButton(
                      label: t.saveName,
                      height: 48,
                      width: 160,
                      fontSize: 14,
                      onPressed: canRename && !_savingName ? _saveName : null,
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(t.winsGames(s.wins, s.games), style: AppText.label(12)),
                        const SizedBox(height: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const PikoCoinIcon(size: 22),
                                const SizedBox(width: 6),
                                Text(formatPicoCoins(s.coins), style: AppText.label(12, color: AppColors.gold)),
                              ],
                            ),
                            Text(t.coinBdtHint, style: AppText.label(10, color: AppColors.textDim)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  canRename || next == null
                      ? t.nameEvery7
                      : t.nameNextChange(
                          '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}',
                        ),
                  style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, height: 1.35, color: AppColors.textDim),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final a in DemoData.avatars)
                      GestureDetector(
                        onTap: () => _update((s) => s.copyWith(avatar: a)),
                        child: FramedTile(
                          size: 56,
                          frameColor: a == s.avatar ? AppColors.active : AppColors.frame,
                          child: AvatarImage(a, size: 56),
                        ),
                      ),
                    GameButton(
                      label: _uploading ? t.uploading : t.uploadPhoto,
                      icon: Icons.cloud_upload_rounded,
                      height: 48,
                      width: 230,
                      fontSize: 13,
                      color: AppColors.frame,
                      onPressed: canUpload && !_uploading ? _uploadAvatar : null,
                    ),
                  ],
                ),
                if (!canUpload)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(t.uploadNeedsServer,
                        style: const TextStyle(
                            fontFamily: 'sans-serif', fontSize: 12, color: AppColors.textDim)),
                  ),
              ],
            ),
          ),
          if (Env.hasBackend && _referral != null)
            SectionCard(
              title: t.sectionPlayerId,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.playerIdHint,
                    style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, height: 1.4, color: AppColors.text),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('${_referral!['code']}', style: AppText.label(28, weight: FontWeight.w900)),
                      const SizedBox(width: 12),
                      GameButton(
                        label: t.copy,
                        height: 42,
                        width: 110,
                        fontSize: 14,
                        color: AppColors.frame,
                        onPressed: () => Clipboard.setData(ClipboardData(text: _referral!['code'] as String)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.referralEarn(_referral!['percent'] as int),
                    style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, height: 1.4, color: AppColors.text),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.invitedCount(_referral!['invited'] as int),
                    style: AppText.label(14, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.referralTotals(
                      '${_referral!['earnedToday']}',
                      '${_referral!['earnedMonth']}',
                      '${_referral!['earned']}',
                    ),
                    style: AppText.label(12, color: AppColors.textDim),
                  ),
                  if (_referral!['people'] is List && (_referral!['people'] as List).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final p in (_referral!['people'] as List).cast<Map<String, dynamic>>())
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          t.referralPerson('${p['name']}', '${p['earned']}'),
                          style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, color: AppColors.text),
                        ),
                      ),
                  ],
                  if (_referral!['referredBy'] == null) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _invite,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: AppText.label(18),
                      decoration: InputDecoration(labelText: t.friendIdOptional, counterText: ''),
                    ),
                    const SizedBox(height: 8),
                    GameButton(
                      label: _applying ? t.saving : t.useId,
                      height: 46,
                      width: 180,
                      fontSize: 14,
                      onPressed: _applying ? null : _applyInvite,
                    ),
                    if (_inviteError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_inviteError!, style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, color: AppColors.danger)),
                      ),
                  ],
                ],
              ),
            ),
          SectionCard(
            title: t.sound,
            child: ChoiceRow<bool>(
              options: {true: t.on, false: t.off},
              value: s.soundOn,
              onChanged: (v) => _update((s) => s.copyWith(soundOn: v)),
            ),
          ),
          if (Env.hasBackend)
            SectionCard(
              title: t.sectionChallenges,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.challengesSettingHint, style: const TextStyle(fontFamily: 'sans-serif', fontSize: 13, height: 1.35, color: AppColors.textDim)),
                  const SizedBox(height: 12),
                  _challengeSwitch(t.challengeReceivePool, s.challengePoolEnabled, (v) => _setChallengeFamily(ChallengeFamily.pool, v)),
                  const SizedBox(height: 8),
                  _challengeSwitch(t.challengeReceiveLudo, s.challengeLudoEnabled, (v) => _setChallengeFamily(ChallengeFamily.ludo, v)),
                  const SizedBox(height: 8),
                  _challengeSwitch(t.challengeReceiveCarrom, s.challengeCarromEnabled, (v) => _setChallengeFamily(ChallengeFamily.carrom, v)),
                ],
              ),
            ),
          SectionCard(
            title: t.sectionShotClock,
            child: ChoiceRow<int>(
              options: {20: t.secLabel(20), 30: t.secLabel(30), 45: t.secLabel(45), 60: t.secLabel(60)},
              value: s.shotSeconds,
              onChanged: (v) => _update((s) => s.copyWith(shotSeconds: v)),
            ),
          ),
          SectionCard(
            title: t.sectionBot,
            child: ChoiceRow<int>(
              options: {0: t.botEasy, 1: t.botNormal, 2: t.botHard},
              value: s.botLevel,
              onChanged: (v) => _update((s) => s.copyWith(botLevel: v)),
            ),
          ),
          SectionCard(
            title: t.sectionSupport,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                GameButton(
                  label: t.facebookSupport,
                  icon: Icons.facebook_rounded,
                  height: 52,
                  width: 220,
                  fontSize: 15,
                  color: const Color(0xFF1877F2),
                  onPressed: () => _openSupport(_facebook),
                ),
                GameButton(
                  label: t.telegramSupport,
                  icon: Icons.send_rounded,
                  height: 52,
                  width: 220,
                  fontSize: 15,
                  color: const Color(0xFF229ED9),
                  onPressed: () => _openSupport(_telegram),
                ),
              ],
            ),
          ),
          SectionCard(
            title: t.sectionLegal,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                GameButton(
                  label: t.privacy,
                  height: 44,
                  width: 160,
                  fontSize: 13,
                  color: AppColors.frame,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LegalScreen(doc: LegalDoc.privacy))),
                ),
                GameButton(
                  label: t.terms,
                  height: 44,
                  width: 160,
                  fontSize: 13,
                  color: AppColors.frame,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LegalScreen(doc: LegalDoc.terms))),
                ),
                GameButton(
                  label: t.conditions,
                  height: 44,
                  width: 180,
                  fontSize: 13,
                  color: AppColors.frame,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LegalScreen(doc: LegalDoc.conditions))),
                ),
              ],
            ),
          ),
          SectionCard(
            title: t.sectionAccount,
            child: GameButton(
              label: t.logout,
              icon: Icons.logout_rounded,
              height: 48,
              width: 220,
              fontSize: 15,
              color: AppColors.danger,
              onPressed: _logout,
            ),
          ),
        ],
      ),
    );
  }
}
