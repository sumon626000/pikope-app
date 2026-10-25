import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/bd_phone.dart';
import '../../core/duel_ui.dart';
import '../../core/env.dart';
import '../../core/widgets.dart';
import '../../core/widgets/bd_phone_field.dart';
import '../../data/api_client.dart';
import '../../l10n/strings.dart';
import '../misc/page_frame.dart';
import '../online/session.dart';
import 'start_route.dart';

/// Forgot password: mobile → SMS OTP → new password → signed in.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialPhoneLocal = ''});

  final String initialPhoneLocal;

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final TextEditingController _phone;
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _otpSent = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: widget.initialPhoneLocal);
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final t = ref.read(stringsProvider);
    final err = BdPhone.validationMessage(_phone.text.trim(), t);
    if (err != null) {
      setState(() {
        _error = err;
        _info = null;
      });
      return;
    }
    if (!Env.hasBackend) {
      setState(() => _error = t.referNeedServer);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(sessionProvider.notifier).forgotPassword(_phone.text.trim());
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _info = t.msgOtpSent;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = t.maybeApi(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePassword() async {
    final t = ref.read(stringsProvider);
    final err = BdPhone.validationMessage(_phone.text.trim(), t);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final code = _code.text.trim();
    if (code.length < 4 || !RegExp(r'^\d+$').hasMatch(code)) {
      setState(() => _error = t.enterOtpFull);
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = t.passwordMin8);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).resetPassword(
            _phone.text.trim(),
            code,
            _password.text,
          );
      if (!mounted) return;
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboarded: true));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => homeScreenFor()),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = t.maybeApi(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return PageFrame(
      title: t.forgotPasswordTitle,
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.forgotPasswordSteps, style: AppText.label(15, color: AppColors.textDim)),
          const SizedBox(height: 16),
          BdPhoneField(
            controller: _phone,
            decoration: InputDecoration(labelText: t.mobile880),
          ),
          if (!_otpSent) ...[
            const SizedBox(height: 20),
            GameButton(
              label: t.sendOtp,
              height: 52,
              fontSize: 16,
              onPressed: _busy ? null : _sendOtp,
            ),
          ] else ...[
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: t.otpSms, counterText: ''),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(labelText: t.newPassword8),
            ),
            const SizedBox(height: 20),
            GameButton(
              label: t.setNewPassword,
              height: 52,
              fontSize: 16,
              color: AppColors.gold,
              onPressed: _busy ? null : _savePassword,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _busy ? null : _sendOtp,
              child: Text(t.resendOtp, style: AppText.label(14, color: AppColors.textDim)),
            ),
          ],
          if (_info != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_info!, style: AppText.label(14, color: DuelColors.gold)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_error!, style: AppText.label(14, color: AppColors.danger)),
            ),
        ],
      ),
    );
  }
}
