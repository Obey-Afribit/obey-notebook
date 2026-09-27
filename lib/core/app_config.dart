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

  static const String appName = 'Universal Notebook';
  static const String appVersion = '0.3.0';

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static const String anthropicApiKey =
      String.fromEnvironment('ANTHROPIC_API_KEY', defaultValue: '');

  /// Public web build. Password-reset emails link here, because a web page can
  /// be opened from any device (a phone's mail app cannot open the APK).
  static const String webAppUrl = String.fromEnvironment(
    'WEB_APP_URL',
    defaultValue: 'https://obey-afribit.github.io/obey-notebook/',
  );

  /// True when cloud sync/auth can be enabled.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// True when AI features should be surfaced.
  static bool get hasAi => anthropicApiKey.isNotEmpty;
}
