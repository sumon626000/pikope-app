import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/env.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../../core/bd_phone.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets/bd_phone_field.dart';
import 'start_route.dart';
import 'forgot_password_screen.dart';
import '../misc/legal_screen.dart';
import '../online/session.dart';
import '../../l10n/strings.dart';

/// Phone sign-up and log in. Opens as soon as the app starts.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

Widget _legalLink(BuildContext context, String label, LegalDoc doc) => GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(doc: doc))),
      child: Text(label, style: AppText.label(18, color: AppColors.active, weight: FontWeight.w800)),
    );

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _referral = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _referral.dispose();
    super.dispose();
  }

  void _enter() {
    FocusManager.instance.primaryFocus?.unfocus();
    final navigator = Navigator.of(context);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboarded: true));
    // Wait until the keyboard connection has detached, then open the lobby.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => homeScreenFor()),
      );
    });
  }

  Future<void> _login() async {
    final l10n = ref.read(stringsProvider);
    final err = BdPhone.validationMessage(_phone.text.trim(), l10n);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = l10n.enterPassword);
      return;
    }
    await _run(() => ref.read(sessionProvider.notifier).login(_phone.text.trim(), _password.text));
  }

  Future<void> _signUp() async {
    final l10n = ref.read(stringsProvider);
    final err = BdPhone.validationMessage(_phone.text.trim(), l10n);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = l10n.passwordMin6);
      return;
    }
    final refCode = _referral.text.trim();
    if (refCode.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(refCode)) {
      setState(() => _error = l10n.referralCodeInvalid);
      return;
    }
    await _run(() => ref.read(sessionProvider.notifier).register(
          _phone.text.trim(),
          _password.text,
          referralCode: refCode,
        ));
  }

  Future<void> _run(Future<void> Function() action) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) _enter();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = ref.read(stringsProvider).maybeApi(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(
      fontFamily: 'sans-serif',
      fontSize: 26,
      color: AppColors.textDim,
    ),
    prefixIcon: Icon(icon, color: AppColors.textDim, size: 36),
    filled: true,
    fillColor: const Color(0xFF16161B),
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.frame, width: 2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.frame, width: 2),
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(audioProvider).playMenuMusic().catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    const input = TextStyle(
      fontFamily: 'sans-serif',
      fontSize: 32,
      color: AppColors.text,
    );
    return DuelCanvas(
      child: Stack(
        children: [
          Positioned(
            left: 120,
            top: 250,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DuelLogo(height: 190),
                const SizedBox(height: 26),
                Text(
                  s.taglineGames,
                  style: AppText.label(
                    24,
                    color: DuelColors.silver,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  s.taglinePick,
                  style: AppText.label(16, color: AppColors.gold),
                ),
              ],
            ),
          ),
          Positioned(
            left: 700,
            top: 24,
            bottom: 24,
            width: 860,
            child: Align(
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.fromLTRB(48, 40, 48, 36),
                decoration: panelDecoration(
                  radius: 32,
                  borderWidth: 3,
                  opacity: 1,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.signUpOrLogin,
                      style: AppText.label(46, weight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      s.loginSubtitle(Env.hasBackend),
                      style: const TextStyle(
                        fontFamily: 'sans-serif',
                        fontSize: 20,
                        height: 1.35,
                        color: AppColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 28),
                    BdPhoneField(
                      controller: _phone,
                      style: input,
                      decoration: _field(s.fieldMobile, Icons.phone_android_rounded),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _password,
                      style: input,
                      obscureText: true,
                      decoration: _field(s.fieldPassword, Icons.lock_rounded),
                    ),
                    if (Env.hasBackend) ...[
                      const SizedBox(height: 20),
                      TextField(
                        controller: _referral,
                        style: input,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _field(s.signupReferralHint, Icons.card_giftcard_rounded),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: GameButton(
                            label: s.signUp,
                            height: 92,
                            fontSize: 28,
                            color: AppColors.gold,
                            onPressed: _busy ? null : _signUp,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: GameButton(
                            label: s.logIn,
                            height: 92,
                            fontSize: 28,
                            onPressed: _busy ? null : _login,
                          ),
                        ),
                      ],
                    ),
                    if (Env.hasBackend) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ForgotPasswordScreen(initialPhoneLocal: _phone.text.trim()),
                            ),
                          ),
                          child: Text(s.forgotPassword, style: AppText.label(20, color: AppColors.textDim)),
                        ),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontFamily: 'sans-serif',
                            fontSize: 22,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: [
                        _legalLink(context, s.privacy, LegalDoc.privacy),
                        Text('·', style: AppText.label(16, color: AppColors.textDim)),
                        _legalLink(context, s.terms, LegalDoc.terms),
                        Text('·', style: AppText.label(16, color: AppColors.textDim)),
                        _legalLink(context, s.conditions, LegalDoc.conditions),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
