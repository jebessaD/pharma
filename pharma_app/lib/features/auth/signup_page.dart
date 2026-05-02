import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_assets.dart';
import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_redirect_cache_provider.dart';
import '../../core/auth/auth_persistence.dart';
import '../../core/shared_preferences_provider.dart';
import '../../core/supabase_config.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _teamName = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  bool _resending = false;
  bool _pendingConfirmation = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    _teamName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
      _successMessage = null;
    });
    var didNavigate = false;

    final email = _email.text.trim();
    final pwd = _password.text;
    final name = _fullName.text.trim();
    final team = _teamName.text.trim();

    try {
      final authRes = await Supabase.instance.client.auth.signUp(
        email: email,
        password: pwd,
        emailRedirectTo: SupabaseConfig.emailRedirectTo,
        data: {'full_name': name, 'team_name': team},
      );

      final user = authRes.user;
      final session = authRes.session;

      final isRepeatedSignup =
          user != null && (user.identities == null || user.identities!.isEmpty);

      if (isRepeatedSignup) {
        if (!mounted) return;
        setState(() {
          _successMessage = null;
          _error = 'This email is already registered. Go back and sign in.';
        });
        return;
      }

      if (session == null && user != null) {
        // No session means email confirmation is still enabled on the project.
        // Try signing in immediately (works if confirmation was just disabled).
        try {
          await Supabase.instance.client.auth.signInWithPassword(
            email: email,
            password: pwd,
          );
        } on AuthException {
          // Sign-in failed (email not confirmed yet). Save pending data and
          // tell the user to check their email then sign in.
          await persistPendingOwnerSignup(
            ref.read(sharedPreferencesProvider),
            email: email,
            teamName: team,
            fullName: name,
          );
          if (!mounted) return;
          setState(() {
            _pendingConfirmation = true;
            _error = null;
            _successMessage =
                'Account created! Check your email for a confirmation link, '
                'then come back and sign in.';
          });
          return;
        }
      }

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        throw Exception('No session after signup');
      }

      await Supabase.instance.client.rpc(
        'bootstrap_owner_team',
        params: {'p_team_name': team, 'p_full_name': name},
      );

      await persistLocalAuthMarker(
        ref.read(sharedPreferencesProvider),
        currentUser,
      );
      ref.invalidate(pharmacyRedirectCacheProvider);
      if (!mounted) return;
      didNavigate = true;
      context.go('/pharmacy/home');
    } on AuthException catch (e) {
      setState(() {
        _successMessage = null;
        _error = userFacingError(e);
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('profile_exists')) {
        // Profile already exists -- just go to home.
        ref.invalidate(pharmacyRedirectCacheProvider);
        if (!mounted) return;
        didNavigate = true;
        context.go('/pharmacy/home');
        return;
      }
      setState(() {
        _successMessage = null;
        _error = userFacingError(e);
      });
    } catch (e) {
      setState(() {
        _successMessage = null;
        _error = userFacingError(e);
      });
    } finally {
      if (!didNavigate && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resendConfirmation() async {
    final email = _email.text.trim();
    if (!email.contains('@')) return;
    setState(() {
      _resending = true;
      _error = null;
      _successMessage = null;
    });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: SupabaseConfig.emailRedirectTo,
      );
      if (!mounted) return;
      setState(() {
        _successMessage =
            'Confirmation email resent to $email. Check your inbox and spam folder.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _successMessage = null;
          _error = userFacingError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Scaffold(
      appBar: pharmacyHubAppBar(
        context,
        title: 'Create pharmacy',
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Image.asset(
                            AppAssets.logo,
                            height: 86,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Pharma Shelf',
                          textAlign: TextAlign.center,
                          style: t.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _teamName,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Pharmacy / team name',
                          ),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.length < 2) {
                              return 'Enter at least 2 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _fullName,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Your full name',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (!s.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            helperText: 'At least 8 characters',
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.length < 8) {
                              return 'Use at least 8 characters';
                            }
                            return null;
                          },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          FormErrorBanner(message: _error!),
                        ],
                        if (_successMessage != null) ...[
                          const SizedBox(height: 12),
                          FormSuccessBanner(message: _successMessage!),
                        ],
                        if (_pendingConfirmation) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: (_loading || _resending)
                                ? null
                                : _resendConfirmation,
                            icon: _resending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.email_outlined, size: 18),
                            label: Text(
                              _resending
                                  ? 'Sending...'
                                  : 'Resend confirmation email',
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Create account'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.pushReplacement('/login'),
                          child:
                              const Text('Already have an account? Sign in'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
