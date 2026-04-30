/// Supabase project ref: jyscupmaxarzzscilvvg
/// Swap for dart-define / env in production.
abstract final class SupabaseConfig {
  static const String url = 'https://jyscupmaxarzzscilvvg.supabase.co';
  static const String anonKey =
      'sb_publishable_sGHJ7UNC9kzyCOA9xvctvQ_dpc1-UW0';

  /// Deep-link scheme registered in AndroidManifest / Info.plist.
  static const String deepLinkScheme = 'pharmaapp';
  static const String deepLinkHost = 'auth';
  static const String emailRedirectTo = '$deepLinkScheme://$deepLinkHost/callback';

  /// The public site URL configured in Supabase Dashboard → Auth → URL Configuration.
  /// Email verification links are built against this. Must NOT be localhost.
  static const String siteUrl = 'https://jyscupmaxarzzscilvvg.supabase.co';
}
