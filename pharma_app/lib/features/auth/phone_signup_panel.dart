import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_persistence.dart';
import '../../core/auth/ethiopian_phone.dart';
import '../../core/auth/request_phone_otp.dart';
import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_redirect_cache_provider.dart';
import '../../core/registration/registration_location.dart';
import '../../core/shared_preferences_provider.dart';
import '../../core/widgets/form_error_banner.dart';
import 'widgets/auth_step_indicator.dart';
import 'widgets/otp_code_field.dart';

enum PhoneSignupStep { details, otp, password }

class PhoneSignupPanel extends ConsumerStatefulWidget {
  const PhoneSignupPanel({super.key, this.onStepChanged});

  /// Notifies parent when user moves past the first step (locks email/phone switch).
  final ValueChanged<PhoneSignupStep>? onStepChanged;

  @override
  ConsumerState<PhoneSignupPanel> createState() => _PhoneSignupPanelState();
}

class _PhoneSignupPanelState extends ConsumerState<PhoneSignupPanel> {
  final _formKey = GlobalKey<FormState>();
  final _teamName = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  PhoneSignupStep _step = PhoneSignupStep.details;
  bool _loading = false;
  bool _resending = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _successMessage;
  EthiopianPhone? _normalizedPhone;
  DateTime? _resendAvailableAt;
  Timer? _resendCooldownTimer;
  int _resendSecondsLeft = 0;

  static const _resendCooldown = Duration(minutes: 2);
  static const _stepLabels = ['Details', 'Verify', 'Password'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreProgress());
  }

  @override
  void dispose() {
    _resendCooldownTimer?.cancel();
    _teamName.dispose();
    _fullName.dispose();
    _phone.dispose();
    _otp.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _setStep(PhoneSignupStep step) {
    setState(() => _step = step);
    widget.onStepChanged?.call(step);
    persistPhoneSignupStep(ref.read(sharedPreferencesProvider), step.name);
  }

  Future<void> _restoreProgress() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final pending = readPendingOwnerSignup(prefs);
    final savedStep = readPhoneSignupStep(prefs);
    final user = Supabase.instance.client.auth.currentUser;
    final pendingPhone = pending.phone?.trim();
    if (pendingPhone == null || pendingPhone.isEmpty) return;

    final normalizedPending = tryNormalizeEthiopianPhone(pendingPhone);
    if (normalizedPending == null) return;

    final userPhone = tryNormalizeEthiopianPhone(user?.phone ?? '');
    final sessionMatchesPhone = user != null &&
        userPhone != null &&
        userPhone.e164 == normalizedPending.e164;

    if (_teamName.text.isEmpty && (pending.teamName?.isNotEmpty ?? false)) {
      _teamName.text = pending.teamName!;
    }
    if (_fullName.text.isEmpty && (pending.fullName?.isNotEmpty ?? false)) {
      _fullName.text = pending.fullName!;
    }
    if (_phone.text.isEmpty) {
      _phone.text = normalizedPending.national;
    }

    _normalizedPhone = normalizedPending;

    if (savedStep == 'password' && sessionMatchesPhone) {
      _setStep(PhoneSignupStep.password);
      setState(() {
        _successMessage =
            'Phone verified. Set a password — you will use it with ${normalizedPending.national} to sign in.';
      });
      return;
    }

    if (savedStep == 'otp') {
      _setStep(PhoneSignupStep.otp);
      setState(() {
        _successMessage = 'Enter the code sent to ${normalizedPending.national}.';
      });
    }
  }

  void _startResendCooldown() {
    _resendAvailableAt = DateTime.now().add(_resendCooldown);
    _tickResendCooldown();
    _resendCooldownTimer?.cancel();
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickResendCooldown();
    });
  }

  void _tickResendCooldown() {
    final availableAt = _resendAvailableAt;
    if (availableAt == null) {
      if (_resendSecondsLeft != 0 && mounted) {
        setState(() => _resendSecondsLeft = 0);
      }
      return;
    }
    final left = availableAt.difference(DateTime.now()).inSeconds;
    final next = left > 0 ? left : 0;
    if (next == 0) {
      _resendAvailableAt = null;
      _resendCooldownTimer?.cancel();
    }
    if (mounted && next != _resendSecondsLeft) {
      setState(() => _resendSecondsLeft = next);
    }
  }

  bool get _canResendOtp => _resendSecondsLeft == 0 && !_loading && !_resending;

  int get _stepIndex => switch (_step) {
    PhoneSignupStep.details => 0,
    PhoneSignupStep.otp => 1,
    PhoneSignupStep.password => 2,
  };

  Future<void> _sendOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phone = tryNormalizeEthiopianPhone(_phone.text);
    if (phone == null) {
      setState(() => _error = ethiopianPhoneValidationMessage());
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final registrationLocation = await inferRegistrationLocation();
      await persistPendingOwnerSignup(
        ref.read(sharedPreferencesProvider),
        phone: phone.e164,
        teamName: _teamName.text.trim(),
        fullName: _fullName.text.trim(),
        registrationLocation: registrationLocation,
      );
      await requestPhoneOtp(
        phoneE164: phone.e164,
        data: {
          'full_name': _fullName.text.trim(),
          'team_name': _teamName.text.trim(),
          ...registrationLocation.toAuthMetadata(),
        },
      );
      if (!mounted) return;
      _normalizedPhone = phone;
      _setStep(PhoneSignupStep.otp);
      setState(() {
        _successMessage =
            'Code sent to ${phone.national}. Valid for 10 minutes.';
        _otp.clear();
      });
      _startResendCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendOtp() async {
    final phone = _normalizedPhone;
    if (phone == null || !_canResendOtp) return;
    setState(() {
      _resending = true;
      _error = null;
      _successMessage = null;
    });
    try {
      await requestPhoneOtp(phoneE164: phone.e164, resend: true);
      if (!mounted) return;
      setState(() {
        _successMessage =
            'Code resent to ${phone.national}. Valid for 10 minutes.';
      });
      _startResendCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final phone = _normalizedPhone;
    if (phone == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.sms,
        phone: phone.e164,
        token: _otp.text.trim(),
      );
      if (response.session == null) {
        throw const AuthException('Verification succeeded but no session was created.');
      }
      if (!mounted) return;
      _setStep(PhoneSignupStep.password);
      setState(() {
        _password.clear();
        _confirmPassword.clear();
        _successMessage =
            'Phone verified. Create a password — you will sign in with ${phone.national} and this password.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _completeSignup() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final phone = _normalizedPhone;
    if (phone == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _successMessage = null;
    });
    var didNavigate = false;

    try {
      final registrationLocation = await inferRegistrationLocation();
      final updateRes = await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (updateRes.user == null) {
        throw const AuthException('Could not save your password. Try again.');
      }

      var currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        throw const AuthException('No session after signup.');
      }

      if (currentUser.phone == null || currentUser.phone!.isEmpty) {
        throw const AuthException('Phone account was not created. Try again.');
      }

      await Supabase.instance.client.rpc(
        'bootstrap_owner_team',
        params: {
          'p_team_name': _teamName.text.trim(),
          'p_full_name': _fullName.text.trim(),
          ...registrationLocation.toRpcParams(),
        },
      );

      final prefs = ref.read(sharedPreferencesProvider);
      await persistLocalAuthMarker(prefs, currentUser);
      await clearPendingOwnerSignup(prefs);
      ref.invalidate(pharmacyRedirectCacheProvider);
      if (!mounted) return;
      didNavigate = true;
      context.go('/pharmacy');
    } on PostgrestException catch (e) {
      if (e.message.contains('profile_exists')) {
        await clearPendingOwnerSignup(ref.read(sharedPreferencesProvider));
        ref.invalidate(pharmacyRedirectCacheProvider);
        if (!mounted) return;
        didNavigate = true;
        context.go('/pharmacy');
        return;
      }
      if (mounted) setState(() => _error = userFacingError(e));
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (!didNavigate && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goBack() async {
    if (_step == PhoneSignupStep.password) {
      _setStep(PhoneSignupStep.otp);
      setState(() {
        _error = null;
        _successMessage = 'Re-enter the code if needed.';
      });
      return;
    }
    await Supabase.instance.client.auth.signOut();
    _setStep(PhoneSignupStep.details);
    setState(() {
      _error = null;
      _successMessage = null;
      _otp.clear();
      _normalizedPhone = null;
    });
    await clearPendingOwnerSignup(ref.read(sharedPreferencesProvider));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthStepIndicator(
            labels: _stepLabels,
            currentIndex: _stepIndex,
          ),
          const SizedBox(height: 20),
          if (_step == PhoneSignupStep.details) ...[
            TextFormField(
              controller: _teamName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Pharmacy / team name',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.length < 2) return 'Enter at least 2 characters';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fullName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter your name';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                hintText: '0911234567',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (v) {
                if (tryNormalizeEthiopianPhone(v ?? '') == null) {
                  return ethiopianPhoneValidationMessage();
                }
                return null;
              },
            ),
          ],
          if (_step == PhoneSignupStep.otp) ...[
            Text(
              'Enter the 6-digit code sent to ${_normalizedPhone?.national ?? ''}',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 12),
            OtpCodeField(
              controller: _otp,
              enabled: !_loading,
              onSubmitted: _loading ? null : _verifyOtp,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _canResendOtp ? _resendOtp : null,
              icon: _resending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sms_outlined, size: 18),
              label: Text(
                _resending
                    ? 'Sending…'
                    : _resendSecondsLeft > 0
                    ? 'Resend in ${_resendSecondsLeft}s'
                    : 'Resend code',
              ),
            ),
          ],
          if (_step == PhoneSignupStep.password) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Phone ${_normalizedPhone?.national ?? ''} verified. '
                      'Choose a password for future sign-in.',
                      style: t.bodySmall?.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: 'At least 8 characters',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.length < 8) {
                  return 'Use at least 8 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPassword,
              obscureText: _obscureConfirm,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) {
                if (v != _password.text) return 'Passwords do not match';
                return null;
              },
              onFieldSubmitted: (_) {
                if (!_loading) _completeSignup();
              },
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            FormErrorBanner(message: _error!),
          ],
          if (_successMessage != null) ...[
            const SizedBox(height: 12),
            FormSuccessBanner(message: _successMessage!),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading
                ? null
                : switch (_step) {
                    PhoneSignupStep.details => _sendOtp,
                    PhoneSignupStep.otp => _verifyOtp,
                    PhoneSignupStep.password => _completeSignup,
                  },
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    switch (_step) {
                      PhoneSignupStep.details => 'Send verification code',
                      PhoneSignupStep.otp => 'Verify & continue',
                      PhoneSignupStep.password => 'Create account',
                    },
                  ),
          ),
          if (_step != PhoneSignupStep.details) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loading ? null : _goBack,
              child: Text(
                _step == PhoneSignupStep.password
                    ? 'Back to code entry'
                    : 'Change phone number',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
