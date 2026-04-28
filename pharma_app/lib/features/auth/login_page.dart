import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/widgets/form_error_banner.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identity = TextEditingController();
  final _password = TextEditingController();
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
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ident = _identity.text.trim();
      final pwd = _password.text;

      if (ident.contains('@')) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: ident,
          password: pwd,
        );
      } else {
        final res = await Supabase.instance.client.functions.invoke(
          'staff-sign-in-username',
          body: {'username': ident, 'password': pwd},
        );
        final d = res.data;
        if (d is! Map) {
          throw Exception('bad_response');
        }
        final at = d['access_token'] as String?;
        final rt = d['refresh_token'] as String?;
        if (at == null || rt == null || at.isEmpty || rt.isEmpty) {
          throw Exception('bad_response');
        }
        await Supabase.instance.client.auth.setSession(rt, accessToken: at);
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('No session after login');
      }

      final adminRow = await Supabase.instance.client
          .from('platform_admins')
          .select('id')
          .eq('auth_user_id', user.id)
          .eq('is_active', true)
          .maybeSingle();
      if (!mounted) return;
      if (adminRow != null) {
        context.go('/admin/teams');
        return;
      }

      ref.invalidate(pharmacyProfileProvider);
      final profile = await ref.read(pharmacyProfileProvider.future);
      if (!mounted) return;
      if (profile == null || profile['is_active'] != true) {
        await Supabase.instance.client.auth.signOut();
        setState(() {
          _error = 'No active access profile was found. Contact your administrator.';
        });
        return;
      }

      context.go('/pharmacy/home');
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Pharmacy access',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _identity,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Username or email',
                      helperText:
                          'Staff: you can use your username, or your full sign-in email if you have one.',
                      helperMaxLines: 3,
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
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Password',
                    ),
                    validator: _validatePassword,
                    onFieldSubmitted: (_) {
                      if (!_loading) _submit();
                    },
                    textInputAction: TextInputAction.done,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    FormErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
