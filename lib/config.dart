/// Build-time configuration, set with `--dart-define`.
///
/// - `ILLINOIS_DINING_URL`: base URL of University Housing's public dining
///   feed (the one the official Illinois app uses). Defaults to the live feed.
/// - `DINING_API_BASE_URL` / `DINING_API_TOKEN`: a custom backend serving
///   this app's own JSON format, including balances (see README).
/// - `USE_SAMPLE_DATA=true`: ignore the above and use built-in sample data.
class AppConfig {
  static const useSampleData = bool.fromEnvironment('USE_SAMPLE_DATA');
  static const illinoisDiningUrl = String.fromEnvironment(
    'ILLINOIS_DINING_URL',
    defaultValue: 'https://web.housing.illinois.edu/MobileAppWS/api',
  );
  static const apiBaseUrl = String.fromEnvironment('DINING_API_BASE_URL');
  static const apiToken = String.fromEnvironment('DINING_API_TOKEN');

  static bool get useIllinoisFeed => !useSampleData && illinoisDiningUrl.isNotEmpty;

  static bool get useCustomBackend => !useSampleData && apiBaseUrl.isNotEmpty;

  static bool get useSampleMenus => !useIllinoisFeed && !useCustomBackend;

  /// Real balances need a University sign-in, so only a custom backend has them.
  static bool get useSampleBalances => !useCustomBackend;

  /// How many days ahead (including today) to keep menus saved for offline use.
  static const prefetchDays = 2;

  /// Days available in the menu date picker.
  static const browseDays = 7;
}
