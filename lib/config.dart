/// Build-time configuration, set with `--dart-define`.
///
/// - `ILLINOIS_DINING_URL`: base URL of University Housing's public dining
///   feed (the one the official Illinois app uses). Defaults to the live feed.
/// - `DINING_API_BASE_URL` / `DINING_API_TOKEN`: a custom backend serving
///   this app's own JSON format, including balances (see README).
/// - `USE_SAMPLE_DATA=true`: ignore the above and use built-in sample data.
///
/// Balances come from University Housing's website after the student signs
/// in with their NetID, unless a custom backend or sample data is used.
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

  static bool get useSampleBalances => useSampleData;

  /// Balances read from University Housing's site after a NetID sign-in.
  static bool get useHousingBalances => !useSampleData && !useCustomBackend;

  /// How many days (including today) of menus to save for offline use, until
  /// the student picks another number in Settings.
  static const defaultOfflineDays = 3;

  /// Days available in the menu date picker.
  static const browseDays = 7;
}
