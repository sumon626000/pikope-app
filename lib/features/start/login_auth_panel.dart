import 'package:flutter/material.dart';
import '../../core/design/pool_city.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/bd_phone.dart';
import '../../core/design/design.dart';
import '../../core/env.dart';
import '../../core/phone_countries.dart';
import '../../core/widgets/international_phone_field.dart';
import '../../data/api_client.dart';
import '../../l10n/strings.dart';
import '../misc/legal_screen.dart';
import '../online/session.dart';
import 'forgot_password_screen.dart';

/// Shared phone sign-up / log-in form (full page or home popup).
class LoginAuthPanel extends ConsumerStatefulWidget {
  const LoginAuthPanel({
    super.key,
    required this.compact,
    required this.onAuthenticated,
  });

  final bool compact;
  final VoidCallback onAuthenticated;

  @override
  ConsumerState<LoginAuthPanel> createState() => _LoginAuthPanelState();
}

class _LoginAuthPanelState extends ConsumerState<LoginAuthPanel> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _referral = TextEditingController();
  late PhoneCountry _country;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _country = PhoneCountries.defaultCountry();
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _referral.dispose();
    super.dispose();
  }

  InputDecoration _field(String label, IconData icon) =>
      DesignAuth.fieldDecoration(label, icon: icon, dense: widget.compact);

  String get _phonePayload => PhoneInput.apiPayload(_phone.text.trim(), _country);

  Future<void> _login() async {
    final l10n = ref.read(stringsProvider);
    final err = PhoneInput.validationMessage(_phone.text.trim(), _country, l10n);
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
          .login(_phonePayload, _password.text),
    );
  }

  Future<void> _signUp() async {
    final l10n = ref.read(stringsProvider);
    final err = PhoneInput.validationMessage(_phone.text.trim(), _country, l10n);
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
          .register(_phonePayload, _password.text, referralCode: refCode),
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
      if (!mounted) return;
      ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(onboarded: true));
      widget.onAuthenticated();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = ref.read(stringsProvider).maybeApi(e.message));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _legalLink(String label, LegalDoc doc) => GestureDetector(
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(doc: doc))),
    child: Text(
      label,
      style: AppText.label(
        widget.compact ? 13 : 26,
        color: AppColors.active,
        weight: FontWeight.w800,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // read: avoid rebuild-on-keyboard MediaQuery churn in compact login dialog.
    final s = ref.read(stringsProvider);
    final compact = widget.compact;
    final titleSize = compact ? 18.0 : 54.0;
    final subSize = compact ? 12.0 : 27.0;
    final inputSize = compact ? 15.0 : 42.0;
    final btnH = compact ? 40.0 : DesignLayout.formButtonHeight + 28;
    final btnFont = compact ? 14.0 : 28.0;
    final errFont = compact ? 13.0 : 28.0;
    final padding = compact
        ? DesignAuth.loginPopupPadding
        : DesignAuth.loginPanelPadding;
    final radius = compact
        ? DesignAuth.loginPopupRadius
        : DesignAuth.loginPanelRadius;

    return Container(
      padding: padding,
      // The popup is a Pool City dialog sheet; the full page sits bare on
      // the page panel.
      decoration: compact
          ? BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A2A7A), Color(0xFF2E2564), Color(0xFF3A2A7A)]),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF8C7CE8), width: 2),
              boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 24, offset: Offset(0, 10))],
            )
          : panelDecoration(radius: radius, borderWidth: 3, opacity: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titleCase(s.signUpOrLogin),
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: pcText(titleSize + (compact ? 2 : 0)),
          ),
          if (!compact) ...[
            SizedBox(height: DesignSpacing.x3),
            Text(
              s.loginSubtitle(Env.hasBackend),
              style: TextStyle(
                fontFamily: DesignTypography.displayFont,
                fontSize: subSize,
                height: 1.35,
                color: AppColors.textDim,
              ),
            ),
          ],
          SizedBox(height: compact ? DesignSpacing.x2 : DesignSpacing.x6),
          InternationalPhoneField(
            controller: _phone,
            country: _country,
            dense: compact,
            onCountryChanged: (c) => setState(() => _country = c),
            style: TextStyle(
              fontFamily: 'sans-serif',
              fontSize: inputSize,
              color: AppColors.text,
            ),
            decoration: _field(s.fieldMobile, Icons.phone_android_rounded),
          ),
          SizedBox(height: compact ? DesignSpacing.x3 : DesignSpacing.x5),
          TextField(
            controller: _password,
            style: TextStyle(
              fontFamily: 'sans-serif',
              fontSize: inputSize,
              color: AppColors.text,
            ),
            obscureText: true,
            decoration: _field(s.fieldPassword, Icons.lock_rounded),
          ),
          if (Env.hasBackend) ...[
            SizedBox(height: compact ? DesignSpacing.x3 : DesignSpacing.x5),
            TextField(
              controller: _referral,
              style: TextStyle(
                fontFamily: 'sans-serif',
                fontSize: inputSize,
                color: AppColors.text,
              ),
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _field(
                s.signupReferralHint,
                Icons.card_giftcard_rounded,
              ),
            ),
          ],
          SizedBox(height: compact ? DesignSpacing.x3 : DesignSpacing.x6),
          if (compact)
            Row(
              children: [
                Expanded(child: PcButton(label: s.signUp, style: PcButtonStyle.gold, height: btnH + 4, fontSize: btnFont + 3, onPressed: _busy ? null : _signUp)),
                const SizedBox(width: DesignSpacing.x3),
                Expanded(child: PcButton(label: s.logIn, style: PcButtonStyle.blue, height: btnH + 4, fontSize: btnFont + 3, onPressed: _busy ? null : _login)),
              ],
            )
          else ...[
            // Reference sign-in: full-width buttons stacked.
            PcButton(label: s.logIn, style: PcButtonStyle.blue, height: 116, fontSize: 44, onPressed: _busy ? null : _login),
            const SizedBox(height: 22),
            PcButton(label: s.signUp, style: PcButtonStyle.gold, height: 116, fontSize: 44, onPressed: _busy ? null : _signUp),
          ],
          if (Env.hasBackend) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ForgotPasswordScreen(
                            initialPhoneLocal: _phone.text.trim(),
                          ),
                        ),
                      ),
                child: Text(
                  s.forgotPassword,
                  style: AppText.label(
                    compact ? 14 : 30,
                    color: AppColors.textDim,
                  ),
                ),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: DesignSpacing.x2),
              child: Text(
                _error!,
                style: TextStyle(
                  fontFamily: DesignTypography.displayFont,
                  fontSize: errFont,
                  color: AppColors.danger,
                ),
              ),
            ),
          SizedBox(height: compact ? DesignSpacing.x2 : DesignSpacing.x4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              _legalLink(s.privacy, LegalDoc.privacy),
              Text(
                '·',
                style: AppText.label(
                  compact ? 12 : 24,
                  color: AppColors.textDim,
                ),
              ),
              _legalLink(s.terms, LegalDoc.terms),
              Text(
                '·',
                style: AppText.label(
                  compact ? 12 : 24,
                  color: AppColors.textDim,
                ),
              ),
              _legalLink(s.conditions, LegalDoc.conditions),
            ],
          ),
        ],
      ),
    );
  }
}
