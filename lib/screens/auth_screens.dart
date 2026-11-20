import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/parent_api.dart';
import '../l10n/l10n.dart';
import '../state/auth.dart';
import '../state/passkeys.dart';
import '../state/settings.dart';
import '../widgets/dombit_logo.dart';
import '../widgets/theme.dart';

/// Frame of the login screens: logo, title, language switch.
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.title, this.subtitle, required this.child, this.onBack});
  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
              child: Row(
                children: [
                  if (onBack != null) IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
                  const Spacer(),
                  for (final l in kLanguages)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 34),
                        backgroundColor: settings.language == l.code ? context.c.accentSoft : null,
                        foregroundColor: settings.language == l.code ? context.c.accentInk : context.c.muted,
                      ),
                      onPressed: () => settings.setLanguage(l.code),
                      child: Text(l.code.toUpperCase(), style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: DombitLogo(height: 180)),
                        const SizedBox(height: 32),
                        Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(subtitle!, style: TextStyle(color: context.c.muted, fontSize: 14)),
                        ],
                        const SizedBox(height: 24),
                        child,
                      ],
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

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      );
}

class FormError extends StatelessWidget {
  const FormError(this.text, {super.key});
  final String? text;
  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0x26F43F5E) : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text!,
          style: TextStyle(color: dark ? const Color(0xFFFDA4AF) : const Color(0xFFBE123C), fontSize: 14)),
    );
  }
}

class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.busy, required this.onPressed});
  final String label;
  final bool busy;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label),
      );
}

/// Groups the 9 digits after +998 as `90 123 45 67`.
class UzPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    // A pasted full number: drop the country code.
    if (digits.length > 9 && digits.startsWith('998')) digits = digits.substring(3);
    if (digits.length > 9) digits = digits.substring(0, 9);
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5 || i == 7) out.write(' ');
      out.write(digits[i]);
    }
    final text = out.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// The only way in: an SMS code to the guardian's phone that the school has
/// on file. No passwords and no DIS code. Step 1 asks for the number, step 2
/// for the code; a login lasts 30 days.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  bool _codeSent = false, _busy = false;
  String? _errorKey;
  int _resendLeft = 0;
  Timer? _timer;

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');
  String get _msisdn => '+998$_digits';

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _resendLeft = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendLeft <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendLeft = 0);
        return;
      }
      setState(() => _resendLeft--);
    });
  }

  Future<void> _send() async {
    if (_busy) return;
    if (_digits.length != 9) {
      setState(() => _errorKey = 'auth.badPhone');
      return;
    }
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      final r = await context.read<ParentApi>().requestSmsCode(_msisdn);
      final result = r['result'] as Map<String, dynamic>? ?? const {};
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _busy = false;
        _code.clear();
      });
      _startCountdown((result['resend_after'] as num?)?.toInt() ?? 60);
      _codeFocus.requestFocus();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorKey = loginErrorKey(e, 'auth.badPhone');
          _busy = false;
        });
      }
    }
  }

  Future<void> _passkey() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await context.read<Auth>().loginWithPasskey();
    } on PasskeyCancelled {
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorKey = passkeyErrorKey(e);
          _busy = false;
        });
      }
    }
  }

  Future<void> _login() async {
    final code = _code.text.trim();
    if (_busy || code.length != 5) return;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await context.read<Auth>().loginWithSms(_msisdn, code);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorKey = loginErrorKey(e, 'auth.wrongSmsCode');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AuthShell(
      title: context.t('auth.title'),
      subtitle: context.t('auth.phoneSubtitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(context.t('auth.phone')),
          TextField(
            controller: _phone,
            enabled: !_codeSent,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [UzPhoneFormatter()],
            style: const TextStyle(fontSize: 17, letterSpacing: 0.5),
            onSubmitted: (_) => _send(),
            // prefixIcon, not prefixText: the code stays visible before the field is tapped.
            decoration: InputDecoration(
              hintText: '90 123 45 67',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Text('+998', style: TextStyle(fontSize: 17, color: c.ink)),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
          if (!_codeSent) ...[
            FormError(_errorKey == null ? null : context.t(_errorKey!)),
            const SizedBox(height: 16),
            BusyButton(label: context.t('auth.sendCode'), busy: _busy, onPressed: _send),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Divider(color: c.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(context.t('passkey.or'), style: TextStyle(color: c.muted, fontSize: 13)),
                ),
                Expanded(child: Divider(color: c.line)),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _busy ? null : _passkey,
              icon: const Icon(Icons.key_outlined, size: 20),
              label: Text(context.t('passkey.signIn')),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              context.t('auth.codeSentTo', {'phone': '+998 ${_phone.text}'}),
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            FieldLabel(context.t('auth.smsCode')),
            TextField(
              controller: _code,
              focusNode: _codeFocus,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace', letterSpacing: 10, fontSize: 22),
              // The fifth digit logs in; no extra tap needed.
              onChanged: (v) {
                if (v.length == 5) _login();
              },
              onSubmitted: (_) => _login(),
              decoration: const InputDecoration(hintText: '•••••'),
            ),
            FormError(_errorKey == null ? null : context.t(_errorKey!)),
            const SizedBox(height: 16),
            BusyButton(label: context.t('auth.logIn'), busy: _busy, onPressed: _login),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _timer?.cancel();
                          setState(() {
                            _codeSent = false;
                            _errorKey = null;
                            _resendLeft = 0;
                          });
                        },
                  child: Text(context.t('auth.changePhone')),
                ),
                TextButton(
                  onPressed: _busy || _resendLeft > 0 ? null : _send,
                  child: Text(_resendLeft > 0
                      ? context.t('auth.resendIn', {'s': _resendLeft})
                      : context.t('auth.resend')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown once after an SMS login: add a passkey so the next login is Face ID
/// or a fingerprint instead of waiting for an SMS.
class PasskeyOfferScreen extends StatefulWidget {
  const PasskeyOfferScreen({super.key});
  @override
  State<PasskeyOfferScreen> createState() => _PasskeyOfferScreenState();
}

class _PasskeyOfferScreenState extends State<PasskeyOfferScreen> {
  bool _busy = false;
  String? _errorKey;

  Future<void> _add() async {
    final auth = context.read<Auth>();
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      await auth.passkeys.add();
      await auth.closePasskeyOffer();
    } on PasskeyCancelled {
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorKey = passkeyErrorKey(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<Auth>();
    return AuthShell(
      title: context.t('passkey.offerTitle'),
      subtitle: context.t('passkey.offerBody'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.fingerprint, size: 72, color: context.c.accent),
          const SizedBox(height: 24),
          FormError(_errorKey == null ? null : context.t(_errorKey!)),
          const SizedBox(height: 8),
          BusyButton(label: context.t('passkey.add'), busy: _busy, onPressed: _add),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _busy ? null : auth.closePasskeyOffer,
            child: Text(context.t('passkey.notNow')),
          ),
        ],
      ),
    );
  }
}
