/// Central runtime configuration.
///
/// Secrets are injected at build/run time via --dart-define and are never
/// committed to source. When Supabase values are absent the app runs in a
/// fully functional local-only mode; when the Anthropic key is absent the AI
/// features are hidden rather than broken.
///
/// Example:
///   flutter run -d windows \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGci... \
///     --dart-define=ANTHROPIC_API_KEY=sk-ant-...
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static const String anthropicApiKey =
      String.fromEnvironment('ANTHROPIC_API_KEY', defaultValue: '');

  /// True when cloud sync/auth can be enabled.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// True when AI features should be surfaced.
  static bool get hasAi => anthropicApiKey.isNotEmpty;
}
