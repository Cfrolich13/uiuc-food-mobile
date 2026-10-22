/// Build-time configuration, set with `--dart-define`.
///
/// With no `DINING_API_BASE_URL`, the app runs on built-in sample data.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('DINING_API_BASE_URL');
  static const apiToken = String.fromEnvironment('DINING_API_TOKEN');

  static bool get useDemoData => apiBaseUrl.isEmpty;

  /// How many days ahead (including today) to keep menus saved for offline use.
  static const prefetchDays = 2;

  /// Days available in the menu date picker.
  static const browseDays = 7;
}
