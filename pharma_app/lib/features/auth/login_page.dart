import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_persistence.dart'
    show
        clearLocalAuthMarker,
        clearPendingOwnerSignup,
        persistLocalAuthMarker,
        readPendingOwnerSignup;
import '../../core/auth/staff_login_email.dart';
import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/branches_list_provider.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/pharmacy_redirect_cache_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/providers/team_shell_meta_provider.dart';
import '../../core/shared_preferences_provider.dart';
import '../../core/supabase_config.dart';
import '../../core/app_assets.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identity = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateIdentity(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Enter your username or email';
    if (t.length < 2) return 'Enter at least 2 characters';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Enter your password';
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    var didNavigate = false;
    try {
      final ident = _identity.text.trim();
      final pwd = _password.text;

      if (ident.contains('@')) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: ident,
          password: pwd,
        );
      } else {
        final syntheticEmail = staffSyntheticLoginEmail(ident);
        try {
          await Supabase.instance.client.auth.signInWithPassword(
            email: syntheticEmail,
            password: pwd,
          );
        } on AuthException {
          final res = await Supabase.instance.client.functions.invoke(
            'staff-sign-in-username',
            body: {
              'username': ident,
              'password': pwd,
            },
          );
          final d = res.data;
          if (d is! Map) throw Exception('bad_response');
          final at = d['access_token'] as String?;
          final rt = d['refresh_token'] as String?;
          if (at == null || rt == null || at.isEmpty || rt.isEmpty) {
            throw Exception('bad_response');
          }
          await Supabase.instance.client.auth.setSession(rt, accessToken: at);
        }
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('No session after login');

      // Check if the user has a profile. If not, try to bootstrap as owner.
      final existingProfile = await Supabase.instance.client
          .from('profiles')
          .select('id, is_active')
          .eq('id', user.id)
          .maybeSingle();

      if (existingProfile == null) {
        // No profile yet: gather team_name + full_name from all available sources.
        final prefs = ref.read(sharedPreferencesProvider);
        final pending = readPendingOwnerSignup(prefs);
        final meta = user.userMetadata ?? const <String, dynamic>{};
        final authEmail = user.email?.trim().toLowerCase() ?? '';
        final pendingEmail = (pending.email ?? '').trim().toLowerCase();
        final isPending = authEmail.isNotEmpty && authEmail == pendingEmail;

        final teamName =
            (isPending ? pending.teamName : null) ??
            (meta['team_name'] as String?) ??
            '';
        final fullName =
            (isPending ? pending.fullName : null) ??
            (meta['full_name'] as String?) ??
            '';

        if (teamName.trim().length >= 2 && fullName.trim().isNotEmpty) {
          await Supabase.instance.client.rpc(
            'bootstrap_owner_team',
            params: {
              'p_team_name': teamName.trim(),
              'p_full_name': fullName.trim(),
            },
          );
          await clearPendingOwnerSignup(prefs);
        } else {
          // Can't bootstrap -- no team info available.
          await Supabase.instance.client.auth.signOut();
          if (!mounted) return;
          setState(() {
            _error =
                'Your account has no pharmacy profile yet. '
                'Please use "New pharmacy signup" to create your pharmacy first.';
          });
          return;
        }
      }

      await persistLocalAuthMarker(ref.read(sharedPreferencesProvider), user);

      // Platform admin check.
      final adminRow = await Supabase.instance.client
          .from('platform_admins')
          .select('id')
          .eq('auth_user_id', user.id)
          .eq('is_active', true)
          .maybeSingle();
      if (!mounted) return;
      if (adminRow != null) {
        didNavigate = true;
        context.go('/admin/teams');
        return;
      }

      ref.invalidate(pharmacyProfileProvider);
      final profile = await ref.read(pharmacyProfileProvider.future);
      if (!mounted) return;
      if (profile == null || profile['is_active'] != true) {
        await Supabase.instance.client.auth.signOut();
        ref.invalidate(pharmacyRedirectCacheProvider);
        final prefsOut = ref.read(sharedPreferencesProvider);
        await clearLocalAuthMarker(prefsOut);
        setState(() {
          _error =
              'Your profile is deactivated. Contact your pharmacy administrator.';
        });
        return;
      }

      final teamId = profile['team_id'] as String?;
      await ref.read(selectedBranchIdProvider.notifier).setBranch(null);
      if (teamId != null && teamId.isNotEmpty) {
        ref.invalidate(teamShellMetaProvider(teamId));
        ref.invalidate(branchesListProvider(teamId));
      }
      ref.invalidate(pharmacyRedirectCacheProvider);

      if (!mounted) return;
      didNavigate = true;
      context.go('/pharmacy/home');
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e));
    } finally {
      if (!didNavigate && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final initialEmail = _identity.text.contains('@') ? _identity.text.trim() : '';
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ForgotPasswordDialog(initialEmail: initialEmail),
    );
    if (sent == true) {
      messenger?.showSnackBar(
        const SnackBar(
          content:
              Text('Reset email sent. Open the link to set a new password.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Scaffold(
      appBar: pharmacyHubAppBar(
        context,
        title: 'Sign in',
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
                        const SizedBox(height: 14),
                        Text(
                          'Use your username or email',
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _identity,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Username or email',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: _validateIdentity,
                          onFieldSubmitted: (_) {
                            if (!_loading) _submit();
                          },
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
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
                          validator: _validatePassword,
                          onFieldSubmitted: (_) {
                            if (!_loading) _submit();
                          },
                          textInputAction: TextInputAction.done,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _loading ? null : _showForgotPasswordDialog,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 4),
                          FormErrorBanner(message: _error!),
                        ],
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Sign in'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.push('/signup'),
                          child: const Text('New pharmacy signup'),
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

// ---------------------------------------------------------------------------
// Forgot-password dialog
// ---------------------------------------------------------------------------

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});
  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  bool _sending = false;
  String? _error;
  late final TextEditingController _emailCtl;

  @override
  void initState() {
    super.initState();
    _emailCtl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailCtl.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: SupabaseConfig.emailRedirectTo,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = userFacingError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter your email and we\'ll send a reset link. Open it to set a new password.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailCtl,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            onSubmitted: (_) => _send(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending ? const Text('Sending...') : const Text('Send link'),
        ),
      ],
    );
  }
}
