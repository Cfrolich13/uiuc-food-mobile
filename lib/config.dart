/// Build-time configuration, set with `--dart-define`.
///
/// - `ILLINOIS_DINING_URL`: base URL of University Housing's dining feed
///   (the one the official Illinois app uses). Enables real menus and hours.
/// - `DINING_API_BASE_URL` / `DINING_API_TOKEN`: a custom backend serving
///   this app's own JSON format, including balances (see README).
///
/// Anything not configured falls back to built-in sample data.
class AppConfig {
  static const illinoisDiningUrl = String.fromEnvironment('ILLINOIS_DINING_URL');
  static const apiBaseUrl = String.fromEnvironment('DINING_API_BASE_URL');
  static const apiToken = String.fromEnvironment('DINING_API_TOKEN');

  static bool get useSampleMenus => illinoisDiningUrl.isEmpty && apiBaseUrl.isEmpty;

  /// Real balances need a University sign-in, so only a custom backend has them.
  static bool get useSampleBalances => apiBaseUrl.isEmpty;

  /// How many days ahead (including today) to keep menus saved for offline use.
  static const prefetchDays = 2;

  /// Days available in the menu date picker.
  static const browseDays = 7;
}
