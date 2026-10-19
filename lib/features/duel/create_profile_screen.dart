import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../../data/demo_data.dart';
import '../../l10n/strings.dart';
import '../online/session.dart';
import 'duel_home_screen.dart';

/// First run: choose an avatar and a nickname (letters, numbers and "_").
class CreateProfileScreen extends ConsumerStatefulWidget {
  const CreateProfileScreen({super.key});

  @override
  ConsumerState<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends ConsumerState<CreateProfileScreen> {
  static final _valid = RegExp(r'^[A-Za-z0-9_]{3,16}$');
  static const _first = ['Genius', 'Lucky', 'Silent', 'Rapid', 'Royal', 'Cosmic', 'Iron', 'Shadow', 'Golden', 'Turbo'];
  static const _second = ['Breaker', 'Shark', 'Hustler', 'Ace', 'Sniper', 'Cue', 'Pocket', 'Striker', 'Baller', 'Wizard'];

  late final TextEditingController _name;
  late String _avatar;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _avatar = DemoData.avatars.contains(s.avatar) ? s.avatar : DemoData.avatars.first;
    _name = TextEditingController(text: _valid.hasMatch(s.name) && s.name != 'PLAYER1' ? s.name : _randomName());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _randomName() {
    final r = Random();
    final name = '${_first[r.nextInt(_first.length)]}_${_second[r.nextInt(_second.length)]}${r.nextInt(90) + 10}';
    return name.substring(0, min(16, name.length));
  }

  Future<void> _submit() async {
    final t = ref.read(stringsProvider);
    final name = _name.text.trim();
    if (!_valid.hasMatch(name)) {
      setState(() => _error = t.nicknameRulesError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).saveProfile(name, _avatar);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const DuelHomeScreen()));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = t.maybeApi(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return DuelCanvas(
        child: Center(
          child: Container(
            width: 880,
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 34),
            decoration: duelPanel(radius: 20, rim: DuelColors.rim, fill: const Color(0xD9121627)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DuelTitle(t.createProfileTitle, size: 46, sub: t.createProfileSub),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(color: const Color(0xFF0D1122), borderRadius: BorderRadius.circular(16)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        for (final a in DemoData.avatars)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: GestureDetector(
                              onTap: () {
                                AudioService.tap();
                                setState(() => _avatar = a);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: a == _avatar ? DuelColors.green : const Color(0xFF2B3566),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [if (a == _avatar) const BoxShadow(color: Color(0x993ED12F), blurRadius: 18)],
                                ),
                                child: ClipRRect(borderRadius: BorderRadius.circular(15), child: AvatarImage(a, size: 124)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                  decoration: BoxDecoration(color: const Color(0xFF0D1122), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 72,
                              padding: const EdgeInsets.only(left: 22, right: 8),
                              decoration: BoxDecoration(color: const Color(0xFF1A2038), borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _name,
                                      maxLength: 16,
                                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_]'))],
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => _submit(),
                                      style: AppText.label(24, color: Colors.white, weight: FontWeight.w800),
                                      cursorColor: DuelColors.green,
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        counterText: '',
                                        hintText: t.usernameHint,
                                        hintStyle: AppText.label(24, color: DuelColors.dim),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(_name.clear),
                                    icon: const Icon(Icons.cancel_rounded, color: Color(0xFF5B6590), size: 40),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          IconButton(
                            tooltip: t.randomNameTip,
                            onPressed: () {
                              AudioService.tap();
                              setState(() => _name.text = _randomName());
                            },
                            icon: const Icon(Icons.casino_rounded, color: Colors.white, size: 54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(_error ?? t.avoidRealName,
                          style: TextStyle(fontFamily: 'sans-serif', fontSize: 18, color: _error == null ? DuelColors.silver : DuelColors.red)),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                DuelButton(label: _busy ? t.saving : t.submit, onPressed: _busy ? null : _submit),
              ],
            ),
          ),
        ),
      );
  }
}
