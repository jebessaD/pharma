/// Supabase client configuration.
///
/// Override at build time with `--dart-define` or `--dart-define-from-file`
/// (see [tool/dart_defines.example.json]). Defaults match the current dev
/// project so `flutter run` and tests work without extra flags.
///
/// Dashboard (Auth → URL configuration): set **Site URL** to the same host as
/// [url] (not localhost). Add [emailRedirectTo] to **Redirect URLs**.
abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jyscupmaxarzzscilvvg.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_sGHJ7UNC9kzyCOA9xvctvQ_dpc1-UW0',
  );

  /// Deep-link scheme registered in AndroidManifest / Info.plist.
  static const String deepLinkScheme = 'pharmaapp';
  static const String deepLinkHost = 'auth';
  static const String emailRedirectTo = '$deepLinkScheme://$deepLinkHost/callback';

  /// Dashboard checklist (Auth → URL configuration):
  /// - Add [emailRedirectTo] to **Redirect URLs** allow list.
  /// - Keep **Confirm email** enabled for signups if you require verification.
  /// - Email templates should use `{{ .ConfirmationURL }}` / `{{ .RedirectTo }}`
  ///   (defaults) so PKCE links include this app redirect, not a stale host.
}
