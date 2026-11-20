/// Build-time configuration, supplied with --dart-define:
///
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// Without them the app runs fully local (no login, no sync).
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get hasCloud => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
