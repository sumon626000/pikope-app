import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/env.dart';
import '../../core/widgets.dart';
import '../../data/api_client.dart';
import '../../core/bd_phone.dart';
import '../../core/design/design.dart';
import '../../core/duel_ui.dart';
import '../../core/widgets/bd_phone_field.dart';
import 'start_route.dart';
import 'forgot_password_screen.dart';
import '../misc/legal_screen.dart';
import '../online/session.dart';
import '../../l10n/strings.dart';

/// Phone sign-up and log in (full screen or popup via [requireRegisteredAccount]).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.popOnSuccess = false});

  /// When true (login popup flow), pop with `true` instead of replacing with home.
  final bool popOnSuccess;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

Widget _legalLink(BuildContext context, String label, LegalDoc doc) =>
    GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(doc: doc))),
      child: Text(
        label,
        style: AppText.label(
          18,
          color: AppColors.active,
          weight: FontWeight.w800,
        ),
      ),
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
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(onboarded: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted) return;
      if (widget.popOnSuccess) {
        navigator.pop(true);
        return;
      }
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
    await _run(
      () => ref
          .read(sessionProvider.notifier)
          .login(_phone.text.trim(), _password.text),
    );
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
    await _run(
      () => ref
          .read(sessionProvider.notifier)
          .register(_phone.text.trim(), _password.text, referralCode: refCode),
    );
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
      if (mounted) {
        setState(() => _error = ref.read(stringsProvider).maybeApi(e.message));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(String label, IconData icon) =>
      DesignAuth.fieldDecoration(label, icon: icon);

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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignSpacing.x10,
          DesignSpacing.x4,
          DesignSpacing.x6,
          DesignSpacing.x4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 5,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: DesignSpacing.x10,
                    right: DesignSpacing.x8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DuelLogo(height: 190),
                      const SizedBox(height: DesignSpacing.x6),
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
              ),
            ),
            Expanded(
              flex: 7,
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: DesignAuth.loginFormMaxWidth,
                    ),
                    child: Container(
                      padding: DesignAuth.loginPanelPadding,
                      decoration: panelDecoration(
                        radius: DesignAuth.loginPanelRadius,
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
                          const SizedBox(height: DesignSpacing.x3),
                          Text(
                            s.loginSubtitle(Env.hasBackend),
                            style: TextStyle(
                              fontFamily: DesignTypography.displayFont,
                              fontSize: 20,
                              height: 1.35,
                              color: AppColors.textDim,
                            ),
                          ),
                          const SizedBox(height: DesignSpacing.x6),
                          BdPhoneField(
                            controller: _phone,
                            style: input,
                            decoration: _field(
                              s.fieldMobile,
                              Icons.phone_android_rounded,
                            ),
                          ),
                          const SizedBox(height: DesignSpacing.x5),
                          TextField(
                            controller: _password,
                            style: input,
                            obscureText: true,
                            decoration: _field(
                              s.fieldPassword,
                              Icons.lock_rounded,
                            ),
                          ),
                          if (Env.hasBackend) ...[
                            const SizedBox(height: DesignSpacing.x5),
                            TextField(
                              controller: _referral,
                              style: input,
                              maxLength: 6,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: _field(
                                s.signupReferralHint,
                                Icons.card_giftcard_rounded,
                              ),
                            ),
                          ],
                          const SizedBox(height: DesignSpacing.x6),
                          Row(
                            children: [
                              Expanded(
                                child: GameButton(
                                  label: s.signUp,
                                  height: DesignLayout.formButtonHeight + 28,
                                  fontSize: 28,
                                  color: AppColors.gold,
                                  onPressed: _busy ? null : _signUp,
                                ),
                              ),
                              const SizedBox(width: DesignSpacing.x5),
                              Expanded(
                                child: GameButton(
                                  label: s.logIn,
                                  height: DesignLayout.formButtonHeight + 28,
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
                                    builder: (_) => ForgotPasswordScreen(
                                      initialPhoneLocal: _phone.text.trim(),
                                    ),
                                  ),
                                ),
                                child: Text(
                                  s.forgotPassword,
                                  style: AppText.label(
                                    20,
                                    color: AppColors.textDim,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: DesignSpacing.x2,
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  fontFamily: DesignTypography.displayFont,
                                  fontSize: 22,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                          const SizedBox(height: DesignSpacing.x4),
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            alignment: WrapAlignment.center,
                            children: [
                              _legalLink(context, s.privacy, LegalDoc.privacy),
                              Text(
                                '·',
                                style: AppText.label(
                                  16,
                                  color: AppColors.textDim,
                                ),
                              ),
                              _legalLink(context, s.terms, LegalDoc.terms),
                              Text(
                                '·',
                                style: AppText.label(
                                  16,
                                  color: AppColors.textDim,
                                ),
                              ),
                              _legalLink(
                                context,
                                s.conditions,
                                LegalDoc.conditions,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
